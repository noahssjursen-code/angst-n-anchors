$godot = "$PSScriptRoot\.godot"

# Remove all cache files except imported/ (keeping imported avoids re-importing audio/textures)
Remove-Item "$godot\global_script_class_cache.cfg" -ErrorAction SilentlyContinue
Remove-Item "$godot\uid_cache.bin"                 -ErrorAction SilentlyContinue
Remove-Item "$godot\scene_groups_cache.cfg"        -ErrorAction SilentlyContinue
Remove-Item "$godot\shader_cache" -Recurse         -ErrorAction SilentlyContinue
Remove-Item "$godot\editor"       -Recurse         -ErrorAction SilentlyContinue

Write-Host "Godot cache cleared. Reopen the project in the editor to rebuild."
Write-Host "(imported/ left intact so assets don't need re-importing)"
