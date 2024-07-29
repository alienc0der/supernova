{ lib
, stdenv
, buildGoApplication
, nix-gitignore
, buildPackages
, coverage ? false # https://tip.golang.org/doc/go1.20#cover
, rocksdb
, network ? "mainnet"  # mainnet|testnet
, rev ? "dirty"
, static ? stdenv.hostPlatform.isStatic
, nativeByteOrder ? true # nativeByteOrder mode will panic on big endian machines
}:
let
  version = "v0.0.2";
  pname = "supernovad";
  tags = [ "ledger" "netgo" network "rocksdb" "grocksdb_no_link" "objstore" ] ++ lib.optionals nativeByteOrder [ "nativebyteorder" ];
  ldflags = lib.concatStringsSep "\n" ([
    "-X github.com/cosmos/cosmos-sdk/version.Name=supernova"
    "-X github.com/cosmos/cosmos-sdk/version.AppName=${pname}"
    "-X github.com/cosmos/cosmos-sdk/version.Version=${version}"
    "-X github.com/cosmos/cosmos-sdk/version.BuildTags=${lib.concatStringsSep "," tags}"
    "-X github.com/cosmos/cosmos-sdk/version.Commit=${rev}"
  ]);
  buildInputs = [ rocksdb ];
  isWindows = stdenv.hostPlatform.isWindows;
  isLinux = stdenv.hostPlatform.isLinux;
  isDarwin = stdenv.isDarwin;
in
buildGoApplication rec {
  inherit pname version buildInputs tags ldflags;
  src = (nix-gitignore.gitignoreSourcePure [
    "/*" # ignore all, then add whitelists
    "!/x/"
    "!/app/"
    "!/cmd/"
    "!/client/"
    "!/versiondb/"
    "!/memiavl/"
    "!/store/"
    "!go.mod"
    "!go.sum"
    "!gomod2nix.toml"
  ] ./.);
  modules = ./gomod2nix.toml;
  pwd = src; # needed to support replace
  subPackages = [ "cmd/cronosd" ];
  buildFlags = lib.optionalString coverage "-cover";
  CGO_ENABLED = "1";
  CGO_LDFLAGS = lib.optionalString (rocksdb != null) (
    if static then "-lrocksdb -pthread -lstdc++ -ldl -lzstd -lsnappy -llz4 -lbz2 -lz"
    else if isWindows then "-lrocksdb-shared"
    else "-lrocksdb -pthread -lstdc++ -ldl"
  );
  
  postFixup = ''
    # Rename the binary to supernovad if on Darwin
    ${lib.optionalString (isDarwin) ''
      mv $out/bin/cronosd $out/bin/supernovad
    ''}
    
    # Adjust the install_name_tool command if on Darwin
    ${lib.optionalString (isDarwin && rocksdb != null) ''
      ${stdenv.cc.bintools.targetPrefix}install_name_tool -change "@rpath/librocksdb.9.dylib" "${rocksdb}/lib/librocksdb.dylib" $out/bin/supernovad
    ''}

    # Rename the binary to supernovad if on Windows
    ${lib.optionalString (isWindows) ''
      mv $out/bin/cronosd.exe $out/bin/supernovad.exe
    ''}
    
    # Rename the binary to supernovad if on Linux
    ${lib.optionalString (isLinux) ''
      mv $out/bin/cronosd $out/bin/supernovad
    ''}
  '';
  
  doCheck = false;
  meta = with lib; {
    description = "Supernova EVM extension-chain";
    homepage = "https://cronos.org/";
    license = licenses.asl20;
    mainProgram = "supernovad" + stdenv.hostPlatform.extensions.executable;
    platforms = platforms.all;
  };
}
