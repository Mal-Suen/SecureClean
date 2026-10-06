# ============================================================
#  SecureClean configuration file
#  Allows overriding auto-detected paths. Copy to secureclean-config.ps1
#  and edit paths as needed. Leave blank/null to use auto-detection.
# ============================================================

# Custom sensitive-data paths (optional overrides)
# If a path is set, the scanner checks it in addition to auto-detected ones.

# Chat apps (WeChat/QQ/WXWork data folders)
$ConfigChatPaths = @(
    # 'D:\WeChat Files',          # example: WeChat data on D drive
    # 'E:\Tencent Files'          # example: QQ data on E drive
)

# Browser user-data folders
$ConfigBrowserPaths = @(
    # 'D:\ChromeData\User Data'   # example: Chrome data elsewhere
)

# Extra sensitive paths to always scan (SSH, tokens, etc.)
$ConfigExtraPaths = @(
    # 'D:\backup\credentials'     # example: a folder with sensitive backups
)

# Extra paths to EXCLUDE from scanning (avoid false positives)
$ConfigExcludePaths = @(
    # 'C:\Users\Public\Desktop'   # example: exclude a shared folder
)
