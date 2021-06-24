with import
  (fetchTarball "https://github.com/nixos/nixpkgs/archive/34cb7885a61c344a22f262520186921843bc7636.tar.gz")
  { };

if !lib.versionAtLeast dotnet-sdk_3.version "3.1" then
  throw "Dotnet sdk has to be atleast 3.1 or newer"
else

  let
    nuget-pkg-json = lib.importJSON ./nuget-packages.json;

    fetchNuGet = callPackage ./fetchnuget.nix { };

    make-nuget-pkg = pkgjson: {
      package = fetchNuGet pkgjson;
      meta = pkgjson;
    };

    make-nuget-pkgset = callPackage ./make-nuget-pkgset.nix { };
    nuget-pkgs = map make-nuget-pkg (nuget-pkg-json);
    test2 = import ./test2.nix;
    nuget-pkg-dir = make-nuget-pkgset "test-nuget-pkgs" nuget-pkgs;

    nuget-config = writeText "nuget.config" ''
      <configuration>
      <packageSources>
          <clear />
          <add key="local" value="${nuget-pkg-dir}" />
      </packageSources>
      </configuration>
    '';

    runtime-config = writeText "runtimeconfig.json" ''
      {
        "runtimeOptions": {
          "additionalProbingPaths": [
            "${nuget-pkg-dir}"
          ]
        }
      }
    '';

    deps = import ./cdn-deps.nix { inherit fetchurl; };
    linkDeps = writeScript "link-deps.sh" (lib.concatMapStringsSep "\n" (hash:
      let prefix = lib.concatStrings (lib.take 2 (lib.stringToCharacters hash));
      in ''
        mkdir -p .git/ue4-gitdeps/${prefix}
        ln -s ${lib.getAttr hash deps} .git/ue4-gitdeps/${prefix}/${hash}
      '') (lib.attrNames deps));
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
  in stdenv.mkDerivation rec {
    pname = "ue5-unrealbuildtool";
    version = "5.0.0";

    unpackPhase = "true";

    configurePhase = ''
      export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
      export DOTNET_CLI_TELEMETRY_OPTOUT=1
      cp ${nuget-config} nuget.config
      export HOME=$TMP

      # Sometimes mono segfaults and things start downloading instead of being
      # deterministic. Let's just fail in that case.
      export http_proxy="nodownloads"

      mkdir -p Engine/Source/Programs
      mkdir -p Engine/Binaries/DotNET/UnrealBuildTool/
      cp -rT ${
        ./UnrealEngine/Engine/Source/Programs
      } Engine/Source/Programs
      chmod -R +rw Engine
      echo "Copy the symlinks for the gitdeps"
      cp -rT ${links} .

      echo "Begin patching shebang"
      #cp ${./Setup.sh} Setup.sh
      #patchShebangs Setup.sh
      #patchShebangs Engine/Build/BatchFiles/Linux
      echo ${nuget-config}
      pushd .
      cd Engine/Source/Programs/UnrealBuildTool && dotnet restore --configfile ${nuget-config}
      popd

      pushd .
      cd Engine/Source/Programs/AutomationTool &&  dotnet restore --configfile ${nuget-config}
      dotnet restore --configfile ${nuget-config} AutomationTool.csproj
      popd

      dotnet msbuild /property:Configuration=Development /nologo Engine/Source/Programs/AutomationTool/AutomationTool.csproj /property:AutomationToolProjectOnly=true
      chmod -R +rw Engine/Binaries
      dotnet msbuild /property:Configuration=Development Engine/Source/Programs/AutomationTool/AutomationTool.proj /nologo  /property:Configuration=Development
    '';

    #./Setup.sh
    #./GenerateProjectFiles.sh
    UE_USE_SYSTEM_MONO = "1";
    UE_USE_SYSTEM_DOTNET = "1";

    installPhase = ''
      mkdir -p $out/bin $out/share/UnrealEngine
      sharedir="$out/share/UnrealEngine"

      mkdir -p "$sharedir/Engine/Binaries"
      cp -r Engine/Binaries "$sharedir/Engine/"

      cat << EOF > $out/bin/UnrealBuildTool
      #! $SHELL -e

      sharedir="$sharedir"
      # Can't include spaces, so can't piggy-back off the other Unreal directory.
      workdir="\$HOME/.config/unreal-engine-nix-workdir"
      if [ ! -e "\$workdir" ]; then
        mkdir -p "\$workdir"
        ${xorg.lndir}/bin/lndir "\$sharedir" "\$workdir"
        unlink "\$workdir/Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool"
        cp "\$sharedir/Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool" "\$workdir/Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool"
      fi

      cd "\$workdir/Engine/Binaries/DotNET/UnrealBuildTool"
      export PATH="${xdg-user-dirs}/bin\''${PATH:+:}\$PATH"
      export LD_LIBRARY_PATH="${libPath}\''${LD_LIBRARY_PATH:+:}\$LD_LIBRARY_PATH"
      exec ./UnrealBuildTool "\$@"
      EOF
      chmod +x $out/bin/UnrealBuildTool
    '';

    #  installPhase = ''
    #    mkdir -p $out/bin $out/share/UnrealEngine
    #
    #    sharedir="$out/share/UnrealEngine"
    #
    #    cat << EOF > $out/bin/UE4Editor
    #    #! $SHELL -e
    #
    #    sharedir="$sharedir"
    #
    #    # Can't include spaces, so can't piggy-back off the other Unreal directory.
    #    workdir="\$HOME/.config/unreal-engine-nix-workdir"
    #    if [ ! -e "\$workdir" ]; then
    #      mkdir -p "\$workdir"
    #      ${xorg.lndir}/bin/lndir "\$sharedir" "\$workdir"
    #      unlink "\$workdir/Engine/Binaries/Linux/UE4Editor"
    #      cp "\$sharedir/Engine/Binaries/Linux/UE4Editor" "\$workdir/Engine/Binaries/Linux/UE4Editor"
    #    fi
    #
    #    cd "\$workdir/Engine/Binaries/Linux"
    #    export PATH="${xdg-user-dirs}/bin\''${PATH:+:}\$PATH"
    #    export LD_LIBRARY_PATH="${libPath}\''${LD_LIBRARY_PATH:+:}\$LD_LIBRARY_PATH"
    #    exec ./UE4Editor "\$@"
    #    EOF
    #    chmod +x $out/bin/UE4Editor
    #
    #    cp -r . "$sharedir"
    #  '';

    buildInputs = [ clang mono which xdg-user-dirs dotnet-sdk_3 ];
  }
