# Upstream Issue Draft — safing/portmaster

**Title:** App profiles break on NixOS after every system rebuild

**Body:**

Hey, I've been running Portmaster on NixOS for a while and there's one thing that really makes it hard to use day-to-day: every time I rebuild my system, all my per-app firewall rules disappear.

## What happens

On NixOS, binaries live in `/nix/store/<hash>-<package-name>/...`. Every system rebuild changes that hash, even if the package itself didn't change. So after a rebuild:

- `/nix/store/raf5jx42...-claude-code-2.1.76/bin/.claude-unwrapped` becomes
- `/nix/store/abc12345...-claude-code-2.1.76/bin/.claude-unwrapped`

Portmaster identifies the app by the full path from `/proc/pid/exe`, sees a new path, creates a new profile. All my block list rules, connection settings — gone. I have to redo them for every app after every rebuild.

This is the same binary, same version, same package. Just a different store hash. NixOS users rebuild frequently (sometimes multiple times a day when tweaking configs), so this makes per-app rules basically unusable.

Guix has the same store path model and would have the same problem.

## What I'd love to see

Something like the existing Flatpak and Snap tag handlers, but for Nix store paths. The pattern is already there in the codebase — Flatpak processes get a `flatpak-id` tag so they match by their Flatpak ID rather than by path. The same approach would work for NixOS:

1. Detect that a binary runs from `/nix/store/`
2. Extract the package name and binary name (strip the volatile hash)
3. Create a tag like `nix-pkg: claude-code:.claude-unwrapped`
4. Profile matches on the tag instead of the path

The tag fingerprint already scores higher than path fingerprint (50k vs 10k base points), so existing matching logic would just work.

More broadly, it'd be great to have some kind of path-pattern or attribute-based profile matching for any system where binary paths aren't stable. NixOS and Guix are the obvious ones, but custom prefix installations or some container setups could benefit too.

## What I'm doing in the meantime

I've written a patch for the [community NixOS package](https://github.com/Daaboulex/portmaster-nix) that adds a `nix_linux.go` tag handler following the exact Flatpak handler pattern. It's a single new file, doesn't touch any existing code. Happy to turn it into a PR if there's interest.

---

**To file:** `gh issue create --repo safing/portmaster --title "App profiles break on NixOS after every system rebuild" --body-file docs/upstream-issue-draft.md`
