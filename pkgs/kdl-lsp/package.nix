{
  lib,
  rustPlatform,
  fetchCrate,
  nix-update-script,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "kdl-lsp";
  version = "6.7.1";

  src = fetchCrate {
    inherit (finalAttrs) pname version;
    hash = "sha256-p+8q5VBhdp/xBG71l5u8IwD7AEtFYOpHsuCvo/WkpNs=";
  };

  cargoHash = "sha256-S7IcKQR4bbJagLjkjW6A2bABNqsIxlnIEWn+PC6N0PI=";

  passthru.updateScript = nix-update-script {
    extraArgs = ["--flake"];
  };

  meta = {
    description = "LSP server for the KDL document language";
    homepage = "https://kdl.dev";
    changelog = "https://github.com/kdl-org/kdl-rs/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "kdl-lsp";
  };
})
