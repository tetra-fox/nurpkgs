{
  lib,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
  nix-update-script,
}:
buildGoModule (finalAttrs: {
  pname = "surge-dm";
  version = "0.12.1";

  src = fetchFromGitHub {
    owner = "SurgeDM";
    repo = "Surge";
    tag = "v${finalAttrs.version}";
    hash = "sha256-cUJwt4gRdlQvMnrEvYG7JZe/2oz4cN9k35TEur13Sks=";
  };

  vendorHash = "sha256-Ei2i7dQ9s42Gg6f2iLABbTG7OQspjHoRnqIhkfcNvFo=";

  # test suite is ~2min of stress tests; not worth running on every rebuild
  doCheck = false;

  # need this to avoid building the sse_auth_server test helper
  subPackages = ["."];

  env.CGO_ENABLED = "0";

  nativeBuildInputs = [installShellFiles];

  ldflags = [
    "-s"
    "-w"
    "-X=github.com/SurgeDM/Surge/cmd.Version=${finalAttrs.version}"
    "-X=github.com/SurgeDM/Surge/cmd.BuildTime=1970-01-01T00:00:00Z"
  ];

  passthru.updateScript = nix-update-script {
    extraArgs = ["--flake"];
  };

  postInstall = ''
    ln -s $out/bin/Surge $out/bin/surge
    installShellCompletion --cmd surge \
      --bash <($out/bin/Surge completion bash) \
      --zsh <($out/bin/Surge completion zsh) \
      --fish <($out/bin/Surge completion fish)
  '';

  meta = {
    description = "Blazing fast TUI download manager built in Go for power users";
    homepage = "https://github.com/SurgeDM/Surge";
    changelog = "https://github.com/SurgeDM/Surge/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "Surge";
    binaryNativeCode = true;
  };
})
