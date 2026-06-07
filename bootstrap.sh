#!/usr/bin/env bash
set -euo pipefail

# --- Colors for Output ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting environment bootstrap...${NC}"

export NEWT_COLORS='
root=,
window=,
border=,
textbox=,
button=,
actbutton=,
checkbox=,
actcheckbox=,
entry=,
label=,
title=,
'

CHOICES=$(whiptail \
    --title "Environment Bootstrap" \
    --checklist "Select tasks to perform:" \
    20 80 10 \
    "install_dependencies" "Install zsh/git/curl" ON \
    "configure_shell" "Set zsh as default shell" ON \
    "install_ohmyzsh" "Install Oh My Zsh" ON \
    "setup_dotfiles" "Clone/update dotfiles" ON \
    "configure_prompt" "Configure prompt" ON \
    3>&1 1>&2 2>&3)

exitstatus=$?

if [ $exitstatus -ne 0 ]; then
    echo "Cancelled."
    exit 1
fi

install_dependencies () {
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
}

configure_shell() {
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
}

install_ohmyzsh() {
    # --- 3. Install Oh My Zsh ---
    export KEEP_ZSHRC=yes # Prevents Oh My Zsh from overwriting an existing .zshrc immediately
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        echo -e "${BLUE}Installing Oh My Zsh...${NC}"
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    else
        echo -e "${GREEN}Oh My Zsh is already installed.${NC}"
    fi
}

setup_dotfiles() {
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
}

configure_prompt() {
    # --- 5. Configure Prompt Prefix ---
    ZSH_LOCAL_ENV="$HOME/.zsh_local"
    touch "$ZSH_LOCAL_ENV" # Ensure the file exists

    # Use whiptail for selection
    PROMPT_CHOICE=$(whiptail --title "Prompt Configuration" \
        --menu "How would you like to configure the 'username@hostname' prompt prefix?" \
        15 60 4 \
        1 "Yes (Always enabled)" \
        2 "No (Disabled)" \
        3 "SSH-Only (Only enabled over SSH connections)" \
        3>&1 1>&2 2>&3)

    exitstatus=$?
    if [ $exitstatus -ne 0 ]; then
        echo -e "${YELLOW}Prompt setup cancelled by user.${NC}"
        return
    fi

    # Define the string to write based on choice
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

    # Update or append PROMPT configuration
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
            awk -v new="$NEW_LINE" '/PROMPT=/ {$0=new} {print}' "$ZSH_LOCAL_ENV" > "${ZSH_LOCAL_ENV}.tmp" \
                && mv "${ZSH_LOCAL_ENV}.tmp" "$ZSH_LOCAL_ENV"
        fi
    else
        if [ -n "$NEW_LINE" ]; then
            echo -e "${BLUE}Adding prompt prefix configuration...${NC}"
            echo -e "\n# Custom prompt prefix\n$NEW_LINE" >> "$ZSH_LOCAL_ENV"
        fi
    fi

    # Ensure .zshrc sources .zsh_local
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
}

for task in $(echo "$CHOICES" | tr -d '"'); do
    "$task"
done

echo -e "${GREEN}Environment bootstrapped successfully! Please restart your terminal.${NC}"
