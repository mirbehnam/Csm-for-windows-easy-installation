import os
from huggingface_hub import login, hf_hub_download
from transformers import AutoTokenizer
from shutil import copyfile
import getpass
import sys

def get_visible_input(prompt):
    print(prompt, end='', flush=True)
    token = ''
    while True:
        char = sys.stdin.read(1)
        if char in ('\n', '\r'):
            print()  # New line after input
            break
        print(char, end='', flush=True)
        token += char
    return token

# Step 1: Get Hugging Face token with visible input
print("\n=== Hugging Face Authentication ===")
print("Please enter your Hugging Face token (visible input):")
print("You can find your token at: https://huggingface.co/settings/tokens")
token = get_visible_input("Token: ")

try:
    # Attempt to login with the provided token
    login(token=token)
    print("✓ Successfully logged in to Hugging Face!")
except Exception as e:
    print(f"❌ Login failed: {str(e)}")
    print("Please check your token and try again.")
    sys.exit(1)

# Define the target directory and filename
current_dir = os.getcwd()  # Get the current working directory
local_dir = os.path.join(current_dir, "csm", "models")  # Path: current_dir/csm/models
filename = "model.safetensors"
local_path = os.path.join(local_dir, filename)  # Full path to the file
repo_id = "sesame/csm-1b"

# Step 2: Create the "csm/models" directory if it doesn’t exist
os.makedirs(local_dir, exist_ok=True)
print(f"Directory '{local_dir}' is ready.")

# Step 3: Check if the file already exists before downloading
if os.path.exists(local_path):
    print(f"{filename} already exists at {local_path}. Skipping download.")
else:
    # Attempt to download only if the file doesn’t exist
    try:
        print(f"Attempting to download {filename} directly to {local_path}...")
        hf_hub_download(
            repo_id=repo_id,
            filename=filename,
            local_dir=local_dir,
            local_dir_use_symlinks=False  # Force copying instead of symlinking
        )
        print(f"Successfully downloaded {filename} to {local_path}.")
    except Exception as e:
        print(f"Direct download failed: {e}")
        # Fallback: Download to cache and copy to the desired location
        print("Falling back to cache download and copy...")
        cache_path = hf_hub_download(repo_id=repo_id, filename=filename)
        copyfile(cache_path, local_path)
        print(f"Copied {filename} from cache to {local_path}.")

# Step 4: Verify the file is in the desired location
if os.path.exists(local_path):
    print(f"{filename} is successfully placed at {local_path}.")
else:
    print(f"Failed to place {filename} at {local_path}.")

# Step 5: Download the tokenizer for meta-llama/Llama-3.2-1B (only once)
tokenizer_name = "meta-llama/Llama-3.2-1B"
print(f"Downloading tokenizer for {tokenizer_name}...")
tokenizer = AutoTokenizer.from_pretrained(tokenizer_name)
print("Tokenizer downloaded and cached successfully.")