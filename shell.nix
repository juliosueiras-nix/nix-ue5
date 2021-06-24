
with import
  (fetchTarball "https://github.com/nixos/nixpkgs/archive/34cb7885a61c344a22f262520186921843bc7636.tar.gz")
  { };
let
    deps = import ./cdn-deps.nix { inherit fetchurl; };
    linkDeps = writeScript "link-deps.sh" (lib.concatMapStringsSep "\n" (hash:
      let prefix = lib.concatStrings (lib.take 2 (lib.stringToCharacters hash));
      in ''
        mkdir -p .git/ue4-gitdeps/${prefix}
        ln -s ${lib.getAttr hash deps} .git/ue4-gitdeps/${prefix}/${hash}
      '') (lib.attrNames deps));
    gitDeps = stdenv.mkDerivation {
      name = "ue5-gitdeps";

      unpackPhase = "true";

      buildInputs = [ mono ];

      buildPhase = ''
        export HOME=$TMP
        mkdir -p Engine/{Build,Plugins}
        cp ${
          ./UnrealEngine/Engine/Build/Commit.gitdeps.xml
        } Engine/Build/Commit.gitdeps.xml
        ${linkDeps}
        export http_proxy="nodownloads"
        mono ${
          ./UnrealEngine/Engine/Binaries/DotNET
        }/GitDependencies.exe --prompt --root=$PWD --cache=$PWD/.git/ue4-gitdeps
      '';

      installPhase = ''
        mkdir -p $out
        cp -r .git $out/
        cp -r .mono $out/
        cp -r .ue* $out/
        cp -r * $out/
      '';
    };
    links = symlinkJoin {
      name = "ue5-gitdeps-link";
      paths = [ gitDeps ];
    };
    libPath = lib.makeLibraryPath [
      xorg.libX11
      xorg.libXScrnSaver
      xorg.libXau
      xorg.libXcursor
      xorg.libXext
      xorg.libXfixes
      xorg.libXi
      xorg.libXrandr
      xorg.libXrender
      xorg.libXxf86vm
      xorg.libxcb
      openssl
    ];
    common = [
      libdrm
      libGL libGL_driver mesa_noglu

      xorg.libX11
      xorg.libXau
      xorg.libxcb
      xorg.libXcursor
      xorg.libXtst
      xorg.libXext
      xorg.libXfixes
      xorg.libXi
      xorg.libXcomposite
      xorg.libXinerama
      xorg.libXrandr
      xorg.libXrender
      xorg.libXScrnSaver
      curl
      xorg.libXxf86vm
      xorg.libXdamage
      zlib
      dotnet-sdk_3
      lttng-ust
      krb5Full
    ];

    LD_LIBRARY_PATH = stdenv.lib.makeLibraryPath([
      stdenv.cc.cc.lib
    ] ++ common);

    test = writeShellScript "test" ''
      cd ~/.config/unreal-engine-nix-workdir
      export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT="1";
      export LD_LIBRARY_PATH="${libPath}";
      export UE_LINKS="${links}"
      export LINUX_MULTIARCH_ROOT=/home/juliosueiras/.config/unreal-engine-nix-workdir/test-sdk/HostLinux/Linux/v17_clang-10.0.1-centos7
      export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${dotnet-sdk_3}/host/fxr/3.1.2:/usr/lib64:${LD_LIBRARY_PATH}:$(find . -name "*.so" | xargs -I % dirname % | uniq | xargs -I % echo $PWD/% | tr '\n' ':')
      export UE_SDKS_ROOT=/home/juliosueiras/.config/unreal-engine-nix-workdir/test-sdk
      export PATH=${llvmPackages_10.clang}/bin:$PATH
      export UBT="${import ./default.nix}/share/UnrealEngine/Engine/Binaries"
      export NIX_CFLAGS_LINK_x86_64_unknown_linux_gnu=" -lc++ -lc++abi -std=c++11"
      export NIX_HARDENING_ENABLE="stackprotector pic strictoverflow format relro bindnow"
      chmod -R +rw ~/.config/unreal-engine-nix-workdir/Engine/Binaries
      cp -r $UBT/* ~/.config/unreal-engine-nix-workdir/Engine/Binaries
      bash
    '';
in (buildFHSUserEnv rec {
  name = "test-unreal";

  runScript = "${test}";

  targetPkgs = pkgs: with pkgs; [
    (import ./default.nix)
    llvmPackages_10.libstdcxxClang
    llvmPackages_10.libcxx
    llvmPackages_10.libcxxabi
    llvmPackages_10.clang-unwrapped.lib
    llvmPackages_10.llvm
    llvmPackages_10.lld
    llvmPackages_10.lldb
    llvmPackages_10.clang.libc.dev
    bashInteractive
    ripgrep 
    ranger screen
    dotnet-sdk_3
    pkg-config
    python2
    mono
    libgcc
    cmake
    udev
    SDL2.dev
    dbus
    alsaLib
    pango
    nspr
    atk
    atkmm
    at-spi2-atk
    nss
    glib
    cairo
    gobject-introspection
    expat
    gio-sharp
    at-spi2-core
    vulkan-loader
    vulkan-tools
    vulkan-validation-layers
  ];
}).env
