#!/usr/bin/env bash
set -euo pipefail

# --- Colors for Output ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting environment bootstrap...${NC}"

# --- 1. Detect OS & Install Zsh ---
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo -e "${BLUE}Detecting macOS. Checking for Homebrew...${NC}"
    if ! command -v brew &> /dev/null; then
        echo -e "${YELLOW}Homebrew not found. Please install Homebrew first or ensure it is in your PATH.${NC}"
        exit 1
    fi
    if ! command -v zsh &> /dev/null; then
        echo "Installing Zsh via Homebrew..."
        brew install zsh
    fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo -e "${BLUE}Detecting Linux...${NC}"
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y zsh git curl
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y zsh git curl
    elif command -v pacman &> /dev/null; then
        sudo pacman -Syu --noconfirm zsh git curl
    else
        echo -e "${YELLOW}Unsupported package manager. Please install zsh, git, and curl manually.${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}Unknown OS type: $OSTYPE. Exiting.${NC}"
    exit 1
fi

# --- 2. Configure Zsh as Default Shell ---
CURRENT_SHELL=$(basename "$SHELL")
if [ "$CURRENT_SHELL" != "zsh" ]; then
    echo -e "${BLUE}Changing default shell to Zsh...${NC}"
    TARGET_ZSH=$(command -v zsh)
    # Check if the shell is registered in /etc/shells (required by chsh on some systems)
    if ! grep -q "$TARGET_ZSH" /etc/shells; then
        echo "$TARGET_ZSH" | sudo tee -a /etc/shells
    fi
    chsh -s "$TARGET_ZSH"
else
    echo -e "${GREEN}Zsh is already the default shell.${NC}"
fi

# --- 3. Install Oh My Zsh ---
export KEEP_ZSHRC=yes # Prevents Oh My Zsh from overwriting an existing .zshrc immediately
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo -e "${BLUE}Installing Oh My Zsh...${NC}"
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    echo -e "${GREEN}Oh My Zsh is already installed.${NC}"
fi

# --- 4. Pull and Install Dotfiles ---
DOTFILES_DIR="$HOME/.dotfiles"
if [ ! -d "$DOTFILES_DIR" ]; then
    echo -e "${BLUE}Cloning dotfiles...${NC}"
    git clone https://github.com/owenlow/dotfiles.git "$DOTFILES_DIR"
else
    echo -e "${GREEN}Dotfiles directory already exists. Pulling latest updates...${NC}"
    git -C "$DOTFILES_DIR" pull
fi

echo -e "${BLUE}Symlinking dotfiles...${NC}"
find "$DOTFILES_DIR" -maxdepth 1 -name ".*" \
    ! -name "." \
    ! -name ".." \
    ! -name ".git" \
    -exec ln -sf {} "$HOME/" \;

# --- 5. Configure Prompt Prefix ---
echo -e "${BLUE}--- Prompt Configuration ---${NC}"
echo "How would you like to configure the 'username@hostname' prompt prefix?"
echo "1) Yes (Always enabled)"
echo "2) No (Disabled)"
echo "3) SSH-Only (Only enabled over SSH connections)"
read -p "Enter your choice (1-3): " -r PROMPT_CHOICE

ZSH_LOCAL_ENV="$HOME/.zsh_local"
touch "$ZSH_LOCAL_ENV" # Ensure the file exists so sed/grep don't complain

# Define the precise string to write based on choice
case "$PROMPT_CHOICE" in
    1)
        NEW_LINE='PROMPT="%{$fg[green]%}%n%{$reset_color%}@%{$fg[blue]%}%m%{$reset_color%} $PROMPT"'
        ;;
    3)
        NEW_LINE='[[ -n $SSH_CONNECTION ]] && PROMPT="%{$fg[green]%}%n%{$reset_color%}@%{$fg[blue]%}%m%{$reset_color%} $PROMPT"'
        ;;
    *)
        NEW_LINE=""
        ;;
esac

# Clean up legacy PS1 configurations from older versions of the script
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' '/PS1=/d' "$ZSH_LOCAL_ENV" 2>/dev/null
else
    sed -i '/PS1=/d' "$ZSH_LOCAL_ENV" 2>/dev/null
fi

# 5a. Update or append the PROMPT configuration
if grep -q "PROMPT=" "$ZSH_LOCAL_ENV"; then
    if [ -z "$NEW_LINE" ]; then
        echo -e "${BLUE}Removing existing prompt prefix configuration...${NC}"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' '/PROMPT=/d' "$ZSH_LOCAL_ENV"
        else
            sed -i '/PROMPT=/d' "$ZSH_LOCAL_ENV"
        fi
    else
        echo -e "${BLUE}Updating existing prompt prefix configuration...${NC}"
        # We use a temporary file for safe cross-platform inline replacement
        awk -v new="$NEW_LINE" '/PROMPT=/ {$0=new} {print}' "$ZSH_LOCAL_ENV" > "${ZSH_LOCAL_ENV}.tmp" && mv "${ZSH_LOCAL_ENV}.tmp" "$ZSH_LOCAL_ENV"
    fi
else
    if [ -n "$NEW_LINE" ]; then
        echo -e "${BLUE}Adding prompt prefix configuration...${NC}"
        echo -e "\n# Custom prompt prefix\n$NEW_LINE" >> "$ZSH_LOCAL_ENV"
    fi
fi

# 5b. Ensure ~/.zshrc actually sources ~/.zsh_local
ZSHRC_PATH="$HOME/.zshrc"
if [ -f "$ZSHRC_PATH" ]; then
    if ! grep -q "\.zsh_local" "$ZSHRC_PATH"; then
        echo -e "${BLUE}Linking .zsh_local to your .zshrc...${NC}"
        echo -e "\n# Source machine-specific configurations\nif [ -f \"\$HOME/.zsh_local\" ]; then\n    source \"\$HOME/.zsh_local\"\nfi" >> "$ZSHRC_PATH"
        echo -e "${GREEN}Successfully added sourcing block to $ZSHRC_PATH${NC}"
    else
        echo -e "${GREEN}.zshrc is already configured to source $ZSH_LOCAL_ENV${NC}"
    fi
else
    echo -e "${YELLOW}Warning: No .zshrc found in $HOME. Make sure your dotfiles include one!${NC}"
fi

echo -e "${GREEN}Prompt setup synchronized.${NC}"

echo -e "${GREEN}Environment bootstrapped successfully! Please restart your terminal.${NC}"
