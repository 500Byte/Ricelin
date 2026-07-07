source /usr/share/cachyos-fish-config/cachyos-config.fish

zoxide init fish | source

abbr -a ff fastfetch

function fish_greeting
    ~/.config/fish/welcome.sh
end
