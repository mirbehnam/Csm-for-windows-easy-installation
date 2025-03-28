import os
import torch
import torchaudio
import gradio as gr
from huggingface_hub import hf_hub_download
from generator import load_csm_1b, Segment
from dataclasses import dataclass
from safetensors.torch import load_file
from generator import Segment, Generator
from models import Model, ModelArgs
# Disable Triton compilation
os.environ["NO_TORCH_COMPILE"] = "1"

# Device selection
if torch.backends.mps.is_available():
    device = "mps"
elif torch.cuda.is_available():
    device = "cuda"
else:
    device = "cpu"

print(f"Using device: {device}")

# Load default prompts
SPEAKER_PROMPTS = {
    "conversational_a": {
        "text": (
            "like revising for an exam I'd have to try and like keep up the momentum because I'd "
            "start really early I'd be like okay I'm gonna start revising now"
        ),
        "audio": hf_hub_download(repo_id="sesame/csm-1b", filename="prompts/conversational_a.wav")
    },
    "conversational_b": {
        "text": (
            "like a super Mario level. Like it's very like high detail. And like, once you get "
            "into the park, it just like, everything looks like a computer game"
        ),
        "audio": hf_hub_download(repo_id="sesame/csm-1b", filename="prompts/conversational_b.wav")
    }
}

# Initialize generator globally
print("Loading CSM model...")


def load_model(device=device):
    model_path = os.path.join("models", "model.safetensors")
    if not os.path.exists(model_path):
        print("Downloading model from Hugging Face...")
        model_path = hf_hub_download(repo_id="sesame/csm-1b", filename="model.safetensors")
    
    model_args = ModelArgs(
        backbone_flavor="llama-1B",
        decoder_flavor="llama-100M",
        text_vocab_size=128256,
        audio_vocab_size=2051,
        audio_num_codebooks=32,
    )
    
    model = Model(model_args).to(device=device, dtype=torch.bfloat16)
    state_dict = load_file(model_path, device=device)
    model.load_state_dict(state_dict)
    return Generator(model)

# Initialize generator globally
print("Loading CSM model...")
generator = load_model()

#generator = load_csm_1b(device)

def get_audio_transcript_pairs():
    sounds_dir = os.path.join(os.path.dirname(__file__), "sounds")
    pairs = []
    
    if os.path.exists(sounds_dir):
        for file in os.listdir(sounds_dir):
            if file.endswith('.wav'):
                base_name = os.path.splitext(file)[0]
                txt_file = base_name + '.txt'
                if os.path.exists(os.path.join(sounds_dir, txt_file)):
                    pairs.append(base_name)
    
    return pairs

def load_audio_transcript_pair(selected_pair):
    if not selected_pair:
        return None, ""
        
    sounds_dir = os.path.join(os.path.dirname(__file__), "sounds")
    audio_path = os.path.join(sounds_dir, selected_pair + '.wav')
    txt_path = os.path.join(sounds_dir, selected_pair + '.txt')
    
    try:
        if not os.path.exists(audio_path):
            return None, ""
            
        with open(txt_path, 'r', encoding='utf-8') as f:
            transcript = f.read().strip()
        
        return audio_path, transcript
        
    except Exception as e:
        print(f"Error loading audio file: {str(e)}")
        return None, ""

def prepare_prompt(text: str, speaker: int, audio_path: str) -> Segment:
    # Load audio and convert to mono if needed
    audio_tensor, sample_rate = torchaudio.load(audio_path)
    
    # Convert to mono if stereo
    if audio_tensor.shape[0] > 1:
        audio_tensor = torch.mean(audio_tensor, dim=0, keepdim=True)
    
    # Resample if needed
    audio_tensor = torchaudio.functional.resample(
        audio_tensor.squeeze(0),
        orig_freq=sample_rate,
        new_freq=generator.sample_rate
    )
    
    return Segment(text=text, speaker=speaker, audio=audio_tensor)

def create_silence(duration_ms: int, sample_rate: int, device: str) -> torch.Tensor:
    """Create a silence tensor of specified duration"""
    num_samples = int(duration_ms * sample_rate / 1000)
    return torch.zeros(num_samples, device=device)
    
def preprocess_text(text):
    lines = text.split('\n')
    cleaned_lines = []
    for line in lines:
        line = line.strip()
        while line and line[0] in ',-._/@#*%$().':
            line = line[1:]
        line = line.strip()
        if line:
            cleaned_lines.append(line)
    text = ', '.join(cleaned_lines)
    text = text.replace(';', ', ').replace(':', ', ')
    text = text.replace("'", "").replace("’", "")
    return text
    

def generate_conversation(speaker1_audio, speaker1_text, speaker2_audio, speaker2_text, conversation_text):
    try:
        # Validate inputs
        if not all([speaker1_audio, speaker1_text, speaker2_audio, speaker2_text, conversation_text]):
            return None, "Error: All inputs are required"

        # Prepare prompts for both speakers
        prompt1 = prepare_prompt(speaker1_text, 0, speaker1_audio)
        prompt2 = prepare_prompt(speaker2_text, 1, speaker2_audio)
        
        # Parse conversation text into turns with preprocessing
        conversation_lines = conversation_text.strip().split('\n')
        conversation = []
        
        for i, line in enumerate(conversation_lines):
            preprocessed_line = preprocess_text(line)
            if preprocessed_line:
                conversation.append({
                    "text": preprocessed_line,
                    "speaker_id": i % 2
                })
        
        if not conversation:
            return None, "Error: Conversation text is empty"

        # Generate each utterance
        generated_segments = []
        prompt_segments = [prompt1, prompt2]
        
        # Create silence tensor
        silence = create_silence(500, generator.sample_rate, device)
        
        for i, utterance in enumerate(conversation, 1):
            print(f"\nProcessing [{i}/{len(conversation)}] Speaker {utterance['speaker_id'] + 1}: {utterance['text']}")
            
            audio_tensor = generator.generate(
                text=utterance['text'],
                speaker=utterance['speaker_id'],
                context=prompt_segments + generated_segments,
                max_audio_length_ms=15_000,
                temperature=0.85
            )
            audio_tensor = audio_tensor.to(device)
            generated_segments.append(
                Segment(text=utterance['text'], 
                       speaker=utterance['speaker_id'], 
                       audio=audio_tensor)
            )
            
            gr.Info(f"Generated {i}/{len(conversation)}: {utterance['text'][:50]}...")
        
        # Concatenate all generations with silence
        all_audio_segments = []
        for i, seg in enumerate(generated_segments):
            all_audio_segments.append(seg.audio)
            if i < len(generated_segments) - 1:
                all_audio_segments.append(silence)
                
        all_audio = torch.cat(all_audio_segments, dim=0)
        
        return (generator.sample_rate, all_audio.cpu().numpy()), "Generation completed successfully!"
        
    except Exception as e:
        import traceback
        return None, f"Error: {str(e)}\n{traceback.format_exc()}"

def create_interface():
    with gr.Blocks(theme=gr.themes.Soft()) as app:
        gr.Markdown("""
        # 🎭 CSM Multi-Speaker Conversation Interface
        Create conversations between two speakers using voice cloning!
        """)
        
        with gr.Row():
            # Speaker 1 column
            with gr.Column():
                gr.Markdown("### 🎤 Speaker 1")
                audio_pairs = get_audio_transcript_pairs()
                speaker1_dropdown = gr.Dropdown(
                    choices=[""] + audio_pairs + ["conversational_a"],
                    label="Select Voice for Speaker 1",
                    value=""
                )
                speaker1_audio = gr.Audio(
                    label="Speaker 1 Reference Voice",
                    type="filepath"
                )
                speaker1_text = gr.Textbox(
                    label="Speaker 1 Reference Text",
                    lines=3
                )
            
            # Speaker 2 column
            with gr.Column():
                gr.Markdown("### 🎤 Speaker 2")
                speaker2_dropdown = gr.Dropdown(
                    choices=[""] + audio_pairs + ["conversational_b"],
                    label="Select Voice for Speaker 2",
                    value=""
                )
                speaker2_audio = gr.Audio(
                    label="Speaker 2 Reference Voice",
                    type="filepath"
                )
                speaker2_text = gr.Textbox(
                    label="Speaker 2 Reference Text",
                    lines=3
                )
        
        # Conversation input
        conversation_input = gr.Textbox(
            label="Enter Conversation (one line per turn)",
            lines=10,
            placeholder="Hello, how are you?\nI'm good, thanks! How about you?\nI'm doing great!"
        )
        
        # Generate button
        generate_btn = gr.Button("🎨 Generate Conversation", variant="primary")
        
        # Output audio
        output_audio = gr.Audio(
            label="Generated Conversation",
            type="numpy"
        )
        
        # Add status output
        status_output = gr.Textbox(
            label="Status",
            interactive=False
        )
        
        # Add progress display
        progress_display = gr.Markdown("Ready to generate...")
        
        def update_speaker_inputs(speaker_num, selected_value):
            if not selected_value:
                return None, ""
            elif selected_value in ["conversational_a", "conversational_b"]:
                prompt = SPEAKER_PROMPTS[selected_value]
                return prompt["audio"], prompt["text"]
            else:
                return load_audio_transcript_pair(selected_value)
        
        speaker1_dropdown.change(
            fn=lambda x: update_speaker_inputs(1, x),
            inputs=[speaker1_dropdown],
            outputs=[speaker1_audio, speaker1_text]
        )
        
        speaker2_dropdown.change(
            fn=lambda x: update_speaker_inputs(2, x),
            inputs=[speaker2_dropdown],
            outputs=[speaker2_audio, speaker2_text]
        )
        
        generate_btn.click(
            fn=generate_conversation,
            inputs=[
                speaker1_audio,
                speaker1_text,
                speaker2_audio,
                speaker2_text,
                conversation_input
            ],
            outputs=[output_audio, status_output]
        )
        
    return app

if __name__ == "__main__":
    app = create_interface()
    app.launch(show_error=True, inbrowser=True)
