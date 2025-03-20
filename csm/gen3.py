import os
import torch
import torchaudio
import subprocess
from huggingface_hub import hf_hub_download
from safetensors.torch import load_file  # <-- import safetensors loader
from generator import Segment
from tqdm import tqdm

# Device selection: Prefer MPS, then CUDA, then CPU.
if torch.backends.mps.is_available():
    device = "mps"
elif torch.cuda.is_available():
    device = "cuda"
else:
    device = "cpu"

print(f"Using device: {device}")

# Define our own load_csm_1b function that combines both approaches
def load_csm_1b_custom(device="cuda"):
    # Import here to avoid circular imports
    from models import Model, ModelArgs
    from generator import Generator
    
    # Path to your .safetensors file
    model_path = os.path.join("models", "model.safetensors")
    if not os.path.exists(model_path):
        print("Local checkpoint not found. Downloading from Hugging Face...")
        model_path = hf_hub_download(repo_id="sesame/csm-1b", filename="model.safetensors")

    
    # Initialize model with args like in the old code
    model_args = ModelArgs(
        backbone_flavor="llama-1B",
        decoder_flavor="llama-100M",
        text_vocab_size=128256,
        audio_vocab_size=2051,
        audio_num_codebooks=32,
    )
    
    # Load the model and state dict
    model = Model(model_args).to(device=device, dtype=torch.bfloat16)
    
    # Load state dict based on file extension
    if model_path.endswith('.pt'):
        print("Loading PyTorch checkpoint...")
        state_dict = torch.load(model_path, map_location=device)
    else:
        print("Loading SafeTensors checkpoint...")
        state_dict = load_file(model_path, device=device)
    
    model.load_state_dict(state_dict)
    return Generator(model)

# Load the CSM model using our custom function
generator = load_csm_1b_custom(device=device)

# Convert MP3 to WAV using ffmpeg (mono audio)
def convert_mp3_to_wav(mp3_path, wav_path):
    print(f"Converting {mp3_path} to mono {wav_path}...")
    subprocess.call(['ffmpeg', '-i', mp3_path, '-ac', '1', wav_path])
    print("Conversion complete.")

# Function to load and resample audio to the model's sample rate.
def load_audio(audio_path):
    if audio_path.endswith('.mp3'):
        wav_path = audio_path.replace('.mp3', '.wav')
        convert_mp3_to_wav(audio_path, wav_path)
        audio_path = wav_path
        
    print(f"Loading audio from {audio_path}...")
    audio_tensor, sample_rate = torchaudio.load(audio_path)
    
    if audio_tensor.shape[0] > 1:
        audio_tensor = torch.mean(audio_tensor, dim=0, keepdim=True)
        print(f"Converted audio to mono: {audio_tensor.shape}")
    
    print(f"Original sample rate: {sample_rate}, converting to {generator.sample_rate}")
    audio_tensor = torchaudio.functional.resample(
        audio_tensor.squeeze(0), orig_freq=sample_rate, new_freq=generator.sample_rate
    )
    
    print(f"Final audio tensor shape: {audio_tensor.shape}")
    return audio_tensor

# Function to generate TTS audio with multiple voice references
def generate_tts_with_voices(text, speakers, transcripts, audio_paths, target_speaker=0, max_audio_length_ms=50_000):
    print("\nInitializing voice generation process...")
    
    # Show progress for loading audio files
    voice_audios = []
    for path in tqdm(audio_paths, desc="1/3 Loading voice references"):
        voice_audios.append(load_audio(path))
    
    # Create context segments with progress bar
    context_segments = []
    for speaker, transcript, audio in tqdm(zip(speakers, transcripts, voice_audios), 
                                         desc="2/3 Creating voice contexts",
                                         total=len(speakers)):
        context_segments.append(
            Segment(text=transcript, speaker=speaker, audio=audio)
        )
    
    print("\n3/3 Generating audio with progress tracking...")
    # Generate audio using all voice contexts (progress bar handled by Generator class)
    audio = generator.generate(
        text=text,
        speaker=target_speaker,
        context=context_segments,
        max_audio_length_ms=max_audio_length_ms
    )
    return audio

# Save the generated audio to a file.
def save_audio(audio, filename="audio.wav"):
    print(f"Saving audio to {filename}...")
    torchaudio.save(filename, audio.unsqueeze(0).cpu(), generator.sample_rate)
    print(f"Audio saved successfully to {filename}")

# --- Example: Generate with multiple voice references ---
try:
    # Define speaker IDs, transcripts, and audio paths
    speakers = [0, 1, 3]  # Speaker IDs can repeat
    transcripts = [
        "Putin invaded Ukraine three years ago. That is a fact. It was not Zelinsky's fault. Zelinsky did not cause his country to be invaded.This is a classic trump emo. It's just that the whole world knows it's wrong, but it was seemed to be part of a deliberate strategy.",
        "Welcome back to 221B stories mystery lovers. Tonight's tale, the whispers of Westminster promises shadows, secrets and suspicious characters. Grab your favorite blanket, dim the lights, and join us as we unravel another Victorian puzzle together.",
        "Your graphics card should have at least 6GB of VRAM, and you should have roughly more than 12GB of RAM. Spark TTS is around 10GB in size, so you'll need 10GB of free space. If you decide to use a CPU instead, you'll need a powerful one along with at least 16GB of RAM."
    ]
    audio_paths = [
        "news_woman.mp3",
        "old_deep.mp3",
        "aroen.mp3"
    ]

    # Text to generate
    text_to_generate = "In this tutorial, I'll walk you through how to easily install Kokoro TTS v1, the most realistic AI text-to-speech model, on your computer. With just two clicks, you can start generating high-quality, offline AI voices in multiple languages—all for free and with no copyright issues! What's New in Kokoro TTS v1? 8 new languages added 54 different voices to choose from Unlimited audio generation (no 30-second limit!) Super realistic voice quality—trained on over 1,000 hours of data!"

    # Generate audio with multiple voice references
    print("Starting multi-voice cloning generation...")
    cloned_audio = generate_tts_with_voices(
        text_to_generate,
        speakers,
        transcripts,
        audio_paths,
        target_speaker=3  # Generate using speaker 3's characteristics
    )

    # Save the generated audio
    save_audio(cloned_audio, "multi_voice_cloned_speech.wav")
    print("Process completed successfully!")
    
except Exception as e:
    print(f"An error occurred: {str(e)}")
    import traceback
    traceback.print_exc()