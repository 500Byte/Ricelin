hl.env("XCURSOR_THEME",   "Bibata-Modern-Ice")
hl.env("XCURSOR_SIZE",    "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- NVIDIA env vars commented out because the system has an AMD RX 580 (amdgpu/Mesa)
-- hl.env("LIBVA_DRIVER_NAME",         "nvidia")
-- hl.env("NVD_BACKEND",               "direct")
-- hl.env("MOZ_DISABLE_RDD_SANDBOX",   "1")
-- hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
-- hl.env("__GL_GSYNC_ALLOWED",        "0")
-- hl.env("__GL_VRR_ALLOWED",          "0")

hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

hl.env("QT_QPA_PLATFORMTHEME", "kde")

-- Force GTK4 to use the ngl renderer to prevent blank/black windows on Hyprland
hl.env("GSK_RENDERER", "ngl")

-- Input method: fcitx5 (dead keys/accents work in GTK3, GTK4 and Qt apps on Wayland)
hl.env("GTK_IM_MODULE", "fcitx")
hl.env("QT_IM_MODULE", "fcitx")
hl.env("XMODIFIERS", "@im=fcitx")
hl.env("INPUT_METHOD", "fcitx")

-- Allow KDE applications like Dolphin to locate application menus on Hyprland
hl.env("XDG_MENU_PREFIX", "plasma-")


