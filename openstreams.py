#!/usr/bin/env python3
import os
import sys
import shutil
import subprocess
import urllib.request
import tty
import termios
import select
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

# Setup Paths & Environment
HOME = os.path.expanduser("~")
LOCAL_BIN = os.path.join(HOME, ".local", "bin")
SLOC = os.path.join(HOME, ".local", "share", "streamonline")
STREAMER_FILE = os.path.join(SLOC, "openstreams_streamers.txt")
LOG_FILE = os.path.join(SLOC, "openstreams.txt")

# CRITICAL FOR NIXOS/GUI LAUNCHERS: Force ~/.local/bin into PATH immediately
if LOCAL_BIN not in os.environ.get("PATH", ""):
    os.environ["PATH"] = f"{LOCAL_BIN}:{os.environ.get('PATH', '')}"


# Ensure directories exist
os.makedirs(SLOC, exist_ok=True)
if not os.path.exists(STREAMER_FILE):
    with open(STREAMER_FILE, "w") as f:
        f.write("best\n")

def get_script_path(name):
    # Search PATH (which now includes ~/.local/bin)
    path = shutil.which(name) or shutil.which(f"{name}.py") or shutil.which(f"{name}.sh")
    if path:
        return path
    
    # Fallback to direct check if PATH search somehow fails
    direct_path = os.path.join(LOCAL_BIN, name)
    if os.path.exists(direct_path):
        return direct_path
        
    return os.path.join(LOCAL_BIN, f"{name}.py")

STREAMONLINE_PATH = get_script_path("streamonline")
OPENSTREAMS_PATH = get_script_path("openstreams")

# --- Helper Functions ---

def check_dependencies():
    for cmd in ["curl", "streamlink"]:
        if not shutil.which(cmd):
            print(f"❌ {cmd} is not installed. Please install it and try again.")
            sys.exit(1)

def get_key():
    """Reads a single keypress without waiting for Enter."""
    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setraw(sys.stdin.fileno())
        ch = sys.stdin.read(1)
        if ch == '\x1b':
            ch += sys.stdin.read(2)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    return ch

def load_streamers():
    if not os.path.exists(STREAMER_FILE):
        return "best", []
    with open(STREAMER_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    if not lines:
        return "best", []
    return lines[0], lines[1:]

def save_streamers(default_quality, entries):
    with open(STREAMER_FILE, "w") as f:
        f.write(f"{default_quality}\n")
        for entry in entries:
            f.write(f"{entry}\n")

# --- Parallel Checker Worker ---

def check_single_streamer(entry, default_quality):
    if "|" in entry:
        url, quality = entry.split("|", 1)
    else:
        url, quality = entry, default_quality

    name = os.path.basename(url.rstrip('/'))
    base_url = os.path.dirname(url) + "/"
    try:
        result = subprocess.run(
            [STREAMONLINE_PATH, "-c", name, "-s", base_url],
            capture_output=True, text=True, timeout=15,
            check=True  # Raises an exception if the command returns a non-zero exit code
        )
        output = result.stdout.strip()
        
    except subprocess.TimeoutExpired:
        output = f"{name} error: command timed out after 15 seconds"
        
    except subprocess.CalledProcessError as e:
        # Captures errors when the command runs but fails (non-zero exit code)
        error_msg = e.stderr.strip() if e.stderr else "Unknown error"
        output = f"{name} error: {error_msg}"
        
    except Exception as e:
        # Captures other unexpected errors (like FileNotFoundError if STREAMONLINE_PATH is wrong)
        output = f"{name} error checking status"

    return {"name": name, "url": url, "quality": quality, "output": output}

# --- Playback Logic with Live Terminal Streaming & Control Bar ---

def play_stream_with_controls(url, quality):
    """Launches streamlink, displays its output live, and keeps a persistent control bar."""
    title_format = "{author} - {category} - {title}"
    
    print(f"\n🎬 Launching {url} with quality {quality}...")
    
    # Define our bottom bar strings
    bar_text = " 🕹️  [s] Skip / Stop current stream and advance "
    styled_bar = f"\033[K\033[44m\033[1;37m{bar_text}\033[0m\n"

    # Launch streamlink pulling text streams back to our script
    process = subprocess.Popen(
        ["streamlink", "--title", title_format, url, quality],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1
    )

    # Make stdin non-blocking so we can interleave reading streamlink text + key hooks
    orig_fl = termios.tcgetattr(sys.stdin.fileno())
    
    try:
        while process.poll() is None:
            # Render the persistent bar at the bottom
            sys.stdout.write(styled_bar)
            sys.stdout.write("\033[1A") # Move cursor back up 1 line to allow stream output scrolling
            sys.stdout.flush()

            # Non-blocking check for both Streamlink output pipe and Keyboard input
            rlist, _, _ = select.select([process.stdout, sys.stdin], [], [], 0.1)
            
            for src in rlist:
                if src == process.stdout:
                    line = process.stdout.readline()
                    if line:
                        # Clear to end of line before printing stream output to avoid bar artifacts
                        sys.stdout.write(f"\033[K{line}")
                        sys.stdout.flush()
                
                elif src == sys.stdin:
                    key = get_key().lower()
                    if key == 's':
                        # Clean up bar space, kill process, and skip out
                        sys.stdout.write("\033[K\n\033[K\033[1A")
                        print("\n⏭️  Skipping current stream...")
                        process.terminate()
                        process.wait()
                        return "skip"
                        
    finally:
        # Clear residual bar artifacts
        sys.stdout.write("\033[K\n\033[K\033[1A")
        sys.stdout.flush()
                
    return "done"

def dothething():
    default_quality, streamer_entries = load_streamers()
    if not streamer_entries:
        print("⚠️ No streamers found in list to check.")
        return

    with open(LOG_FILE, "w") as f:
        f.write("")

    online_streamers = []
    batch_size = 4
    
    print("🕵️  Checking all streamers in parallel batches of 4...")

    for i in range(0, len(streamer_entries), batch_size):
        batch = streamer_entries[i:i+batch_size]
        
        with ThreadPoolExecutor(max_workers=batch_size) as executor:
            futures = {executor.submit(check_single_streamer, entry, default_quality): entry for entry in batch}
            
            for future in as_completed(futures):
                res = future.result()
                if res:
                    print(res["output"])
                    with open(LOG_FILE, "a") as f:
                        f.write(res["output"] + "\n")

                    if "online" in res["output"].lower():
                        online_streamers.append((res["url"], res["quality"]))

    print("\n-----------------")
    if not online_streamers:
        print("\033[0;31m🚫 Nobody is online\033[0m")
    else:
        print("🟢 Online Streams Found:")
        with open(LOG_FILE, "r") as f:
            for line in f:
                if "online" in line.lower():
                    print(line.strip())
        print("-----------------")
        
        for url, quality in online_streamers:
            status = play_stream_with_controls(url, quality)
            if status == "skip":
                time.sleep(0.5)
                continue

# --- UI Menus ---

def update_scripts():
    print("🔄 Updating scripts from GitHub...")
    # Updated paths and files targeted from repository
    urls = {
        STREAMONLINE_PATH: "https://raw.githubusercontent.com/usr40k/streamonline/main/streamonline.sh",
        OPENSTREAMS_PATH: "https://raw.githubusercontent.com/usr40k/streamonline/main/openstreams.py"
    }
    try:
        for path, url in urls.items():
            os.makedirs(os.path.dirname(path), exist_ok=True)
            urllib.request.urlretrieve(url, path)
            os.chmod(path, 0o755)
            print(f"✅ Saved and made executable: {path}")
        print("✅ Scripts updated successfully.")
    except Exception as e:
        print(f"❌ Failed to update scripts: {e}")
    sys.exit(0)

def add_streamer():
    default_quality, entries = load_streamers()
    url = input("🔗 Paste full stream URL (or press Enter to cancel): ").strip()
    if not url:
        print("❌ No URL provided. Canceling.")
        return

    quality = input(f"🎚️ Enter preferred quality (or press Enter for default: {default_quality}): ").strip()
    quality = quality if quality else default_quality

    if any(e.startswith(url + "|") or e == url for e in entries):
        print(f"⚠️ {url} is already in the list.")
        return

    entry = url if quality == default_quality else f"{url}|{quality}"
    entries.append(entry)
    save_streamers(default_quality, entries)
    print(f"✅ Added {url} with quality {quality}.")

def manual_stream():
    default_quality, _ = load_streamers()
    url = input("🔗 Paste full stream URL (or press Enter to cancel): ").strip()
    if not url:
        print("❌ No URL provided. Canceling.")
        return

    print("Checking available streams...")
    proc = subprocess.Popen(["streamlink", url], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for line in proc.stdout:
        if "Available streams:" in line:
            print(line.strip())
    proc.wait()

    qlty = input(f"🎚️ Enter desired quality (or press Enter for default: {default_quality}): ").strip()
    qlty = qlty if qlty else default_quality
    
    title_format = "{author} - {category} - {title}"
    subprocess.run(["streamlink", "--title", title_format, url, qlty])

def clear_logs():
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)
    for f in os.listdir(SLOC):
        if f.endswith("prog_state.txt"):
            os.remove(os.path.join(SLOC, f))
    print("Components cleared 🧹")

def manage_streamers():
    selected = 0
    while True:
        default_quality, entries = load_streamers()
        if not entries:
            entries = ["(List empty - press 'a' to add)"]
        
        os.system('clear')
        print("🛞  Manage Streamers:")
        print("Use Up/Down arrows to scroll. 'a' to add, 'r' to remove, 'e' to edit, 'q' to quit.")
        print("↕️  Press 'K' (Shift+k) to move UP, 'J' (Shift+j) to move DOWN.\n")

        for i, entry in enumerate(entries):
            if i == selected and entries[0] != "(List empty - press 'a' to add)":
                print(f"  \033[1;32m> {entry}\033[0m")
            else:
                print(f"    {entry}")

        key = get_key()
        has_items = entries and entries[0] != "(List empty - press 'a' to add)"

        if key == '\x1b[A':
            selected = (selected - 1) % len(entries)
        elif key == '\x1b[B':
            selected = (selected + 1) % len(entries)
        elif key == 'K' and has_items:
            if selected > 0:
                entries[selected], entries[selected - 1] = entries[selected - 1], entries[selected]
                selected -= 1
                save_streamers(default_quality, entries)
        elif key == 'J' and has_items:
            if selected < len(entries) - 1:
                entries[selected], entries[selected + 1] = entries[selected + 1], entries[selected]
                selected += 1
                save_streamers(default_quality, entries)
        elif key == 'a':
            add_streamer()
            input("\nPress Enter to continue...")
        elif key == 'r' and has_items:
            to_remove = entries[selected]
            entries.remove(to_remove)
            save_streamers(default_quality, entries)
            print(f"✅ Removed {to_remove.split('|')[0]}")
            selected = max(0, selected - 1)
            time.sleep(1)
        elif key == 'e' and has_items:
            current_entry = entries[selected]
            url = current_entry.split('|')[0]
            curr_q = current_entry.split('|')[1] if '|' in current_entry else default_quality
            
            print(f"\n🔗 Current URL: {url}")
            print(f"🎚️  Current quality: {curr_q}")
            new_url = input("Enter new URL (or press Enter to keep current): ").strip() or url
            new_q = input(f"Enter new quality (or press Enter to keep current: {curr_q}): ").strip() or curr_q
            
            entries[selected] = new_url if new_q == default_quality else f"{new_url}|{new_q}"
            save_streamers(default_quality, entries)
            print("✅ Updated successfully.")
            time.sleep(1)
        elif key == 'q':
            break

def menu():
    print("\n📺 Choose an option:")
    print("(1) Automatic (10s timeout active)")
    print("(2) Choose stream manually")
    print("(3) Clear logs")
    print("(4) Manage streamers")
    print("(5) Update or install scripts")
    print("(6) Exit")
    print(">>> ", end="", flush=True)

    rlist, _, _ = select.select([sys.stdin], [], [], 10)
    if rlist:
        action = sys.stdin.readline().strip()
    else:
        print("\n⏱️  Timeout. Proceeding automatically...")
        action = "1"

    action = action if action else "1"

    if action == "1":
        dothething()
    elif action == "2":
        manual_stream()
    elif action == "3":
        clear_logs()
    elif action == "4":
        manage_streamers()
    elif action == "5":
        update_scripts()
    elif action == "6":
        print("👋 Exiting.")
        sys.exit(0)
    else:
        print("Invalid input. Proceeding automatically...")
        dothething()

if __name__ == "__main__":
    check_dependencies()
    if len(sys.argv) > 1 and sys.argv[1] in ["--update", "--install"]:
        update_scripts()
    menu()
