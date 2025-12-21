## Build Status

| Package | Arch Linux | Arch Linux (Git) | Flatpak |
|---------|------------|------------------|---------|
| **live-backgroundremoval-lite** | [![Build](https://github.com/kaito-tokyo/live-plugins-hub/actions/workflows/build-arch-live-backgroundremoval-lite.yaml/badge.svg)](https://github.com/kaito-tokyo/live-plugins-hub/actions/workflows/build-arch-live-backgroundremoval-lite.yaml) | [![Build](https://github.com/kaito-tokyo/live-plugins-hub/actions/workflows/build-arch-live-backgroundremoval-lite-git.yaml/badge.svg)](https://github.com/kaito-tokyo/live-plugins-hub/actions/workflows/build-arch-live-backgroundremoval-lite-git.yaml) | [![Build](https://github.com/kaito-tokyo/live-plugins-hub/actions/workflows/build-flatpak-live-backgroundremoval-lite.yaml/badge.svg)](https://github.com/kaito-tokyo/live-plugins-hub/actions/workflows/build-flatpak-live-backgroundremoval-lite.yaml) |


# Live Plugins Hub 🎥

Welcome! This repository contains packaging definitions for our Live Plugins for OBS Studio, specifically for **Arch Linux** and **Flatpak** users.

Currently, we maintain packaging files for:

- **Live Background Removal Lite** - A lightweight background removal plugin for OBS Studio

---

## 📦 Installation Methods

### For Arch Linux Users

#### ⚠️ Important Notice: Not Available on the AUR

The `PKGBUILD` files in this repository are provided for users who wish to build the plugin from source on Arch Linux.

Currently, this plugin is **not officially available on the Arch User Repository (AUR)**. To publish and maintain packages on the AUR, we need a dedicated volunteer from the community to act as a maintainer.

**We are actively looking for a volunteer to maintain the AUR packages for `live-backgroundremoval-lite`.** If you are an experienced Arch Linux user and are interested in helping the community by maintaining the `PKGBUILD`s, please get in touch with us by opening an issue in this repository.

#### Building from This Repository (Manual Installation)

If you wish to proceed with building the plugin from these local files, you will need the standard Arch Linux build tools.

##### Prerequisites

Ensure you have the `base-devel` group and `git` installed on your system:

```bash
sudo pacman -S --needed base-devel git
```

##### Build and Install Steps

1.  Clone the repository:

    ```bash
    git clone https://github.com/kaito-tokyo/live-plugins-hub.git
    cd live-plugins-hub/arch
    ```

2.  Navigate to the directory of the version you want to build:
    - **For a specific release version (stable):**
      ```bash
      cd live-backgroundremoval-lite
      ```
    - **For the latest development version:**
      ```bash
      cd live-backgroundremoval-lite-git
      ```

3.  Use `makepkg` to build and install the package:
    - The `-s` flag installs necessary dependencies from the official repositories.
    - The `-i` flag installs the package after a successful build.

    ```bash
    makepkg -si
    ```

This will build the package from the sources defined in the `PKGBUILD` and install it on your system. Please remember that this is considered an unsupported installation method.

---

### For Flatpak Users

#### ⚠️ Important Notice: Source Code Only

The files in this repository are provided for users who wish to build the plugin from source using Flatpak.

**This repository does not provide any pre-built binary packages.** The only official way to obtain a pre-built binary will be through **Flathub**, once the plugin is registered and published there by a community maintainer.

##### Call for Maintainers

Currently, this plugin is **not available on Flathub**. To publish and maintain an application on Flathub, we need a dedicated volunteer from the community.

**We are actively looking for a volunteer to maintain the Flatpak package for `live-backgroundremoval-lite`.** If you are an experienced Flatpak packager and are interested in helping the community, please get in touch with us by opening an issue in this repository.

#### Building from This Repository (Manual Installation)

If you wish to proceed with building the plugin from these local files, you will need `flatpak` and `flatpak-builder`.

##### Prerequisites

1.  **Install Flatpak and Flatpak Builder.**
    Follow the official instructions for your distribution to install `flatpak`. Then, install `flatpak-builder`.

    ```bash
    # On Fedora/CentOS
    sudo dnf install flatpak-builder
    # On Debian/Ubuntu
    sudo apt install flatpak-builder
    # On Arch Linux
    sudo pacman -S flatpak-builder
    ```

2.  **Set up the Flathub remote and install necessary components.**
    The build process requires the KDE SDK, and you will need the OBS Studio Flatpak to run the plugin.

    ```bash
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak install flathub org.kde.Sdk//6.8 com.obsproject.Studio
    ```

##### Build and Install Steps

1.  Clone the repository and navigate to the `flatpak` directory:

    ```bash
    git clone https://github.com/kaito-tokyo/live-plugins-hub.git
    cd live-plugins-hub/flatpak/com.obsproject.Studio.Plugin.LiveBackgroundRemovalLite
    ```

2.  Use `flatpak-builder` to build and install the plugin:
    - The `--user` flag installs the plugin for the current user.
    - The `--install` flag installs the plugin after a successful build.
    - `build-dir` is a temporary directory for the build process.

    ```bash
    flatpak-builder --user --install --force-clean build-dir com.obsproject.Studio.Plugin.LiveBackgroundRemovalLite.json
    ```

This will build the plugin and all its dependencies from source and install it as an extension for the OBS Studio Flatpak. Once complete, you can run OBS Studio, and the plugin will be available.

```bash
flatpak run com.obsproject.Studio
```

---

## 🤝 Contributing

We welcome contributions! If you're interested in:

- Maintaining the AUR packages
- Maintaining the Flathub package
- Improving the packaging definitions
- Reporting issues or suggesting improvements

Please feel free to open an issue or submit a pull request!

---

## 📄 License

This repository is licensed under the CC0 1.0 Universal License. See the [LICENSE](LICENSE) file for details.

The plugins themselves may be under different licenses. Please refer to their respective repositories for more information.
