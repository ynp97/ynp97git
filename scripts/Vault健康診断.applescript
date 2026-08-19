on run
    set checkScript to quoted form of "/Users/yoshiakinagumo/Documents/Obsidian Vault/scripts/vault_health_check.sh"
    tell application "Terminal"
        activate
        do script "clear; " & checkScript & "; printf '\\n\\n診断が終わりました。この画面は閉じて構いません。\\n'"
    end tell
end run
