#!/bin/bash

(
    runuser -l abc -c 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" --unattended'

    # The omz install.sh does `git clone --depth=1`, which makes `omz update`
    # fail later with "Could not read <hash>" when parents get GC'd on origin.
    # Unshallow to a full clone so future updates work reliably.
    if [ -d "$HOME/.oh-my-zsh/.git" ]; then
        runuser -l abc -c 'cd "$HOME/.oh-my-zsh" && git fetch --unshallow origin 2>/dev/null || true'
    fi

    ZSHRC="$HOME/.zshrc"
    TARGET_LINE='export PATH="\$HOME/.local/bin:\$PATH"'

    # 1. Check if ~/.zshrc exists
    if [ -f "$ZSHRC" ]; then
        echo "[start-ohmyzsh] ~/.zshrc found. Checking PATH configuration..."
        # 2. Check if the specific PATH line is already set in the file
        if grep -Fxq 'export PATH=$HOME/.local/bin:$PATH' "$ZSHRC"; then
            echo "[start-ohmyzsh] PATH is already correctly configured in ~/.zshrc."
        else
            # 3. If not set, append it
            runuser -l abc -c "echo $TARGET_LINE >> $ZSHRC"
            echo "[start-ohmyzsh] Successfully added ~/.local/bin to your PATH in ~/.zshrc."
        fi
    else
        echo "[start-ohmyzsh] Error: ~/.zshrc does not exist. Skipping configuration."
    fi
) &