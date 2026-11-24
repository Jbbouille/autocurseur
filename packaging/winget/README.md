# winget package

`manifests/` mirrors the layout of [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs): the 0.1.0 manifests of `Jbbouille.AutoCurseur` (portable installer, x64, the exe of the GitHub release, its SHA-256, descriptions in English and French).

Check them with:

```powershell
winget validate --manifest packaging\winget\manifests\j\Jbbouille\AutoCurseur\0.1.0
```

## First version

The first version is added by a pull request to `microsoft/winget-pkgs` that copies `manifests/j/Jbbouille/AutoCurseur/0.1.0/` to the same path. Microsoft's pipeline then downloads the exe, checks the hash, scans it, installs it in a virtual machine, and a moderator merges the pull request. On a first contribution, the Microsoft contributor license agreement (CLA) must be accepted in the pull request.

Once merged:

```powershell
winget install Jbbouille.AutoCurseur
```

winget copies the exe under `%LOCALAPPDATA%\Microsoft\WinGet\Packages\` and adds the `autocurseur` command. Quit AutoCurseur before `winget upgrade`, since a running exe cannot be replaced. `winget uninstall` removes the exe but not the settings (`HKCU\Software\AutoCurseur`), the cursor files (`%LOCALAPPDATA%\AutoCurseur`) nor the *Start with Windows* entry: untick that option before uninstalling.

## Next versions

The release job of the [CI](../../.github/workflows/ci.yml) submits each new `v*` tag to winget with [Komac](https://github.com/russellbanks/Komac), which takes the hash, date and release notes from the GitHub release. It only runs if the repository has a `WINGET_TOKEN` secret: a **classic** GitHub token with the `public_repo` scope, from the account that opens the pull requests (Komac forks `winget-pkgs` to it).
