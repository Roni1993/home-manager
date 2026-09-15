{ pkgs, lib, misc, ... }:
let
  completionSpec = name: text: pkgs.writeText "carapace-${name}.yaml" text;
in {
  # Programs with Home Manager modules that are shared across all profiles.
  # Work- or private-specific program enables live in profiles/work.nix
  # and profiles/private.nix respectively.

  programs.opencode.enable = true;
  # The nixpkgs opencode build (patchelf'd Bun binary) segfaults on WSL2 —
  # https://github.com/NixOS/nixpkgs/issues/520383. Use the official static
  # release binary instead. Bump version + sha256 to upgrade.
  programs.opencode.package = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "opencode";
    version = "1.18.5";
    src = pkgs.fetchurl {
      url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-linux-x64.tar.gz";
      sha256 = "1qpaq5s8lhp645hqpnmy6jxqhcypx3mmf0jwrckhymfnldbjajnd";
    };
    dontUnpack = true;
    installPhase = ''
      tar -xzf $src
      install -Dm755 opencode $out/bin/opencode
    '';
  };

  programs.dircolors.enable = true;
  programs.nushell.enable = true;
  programs.gh.enable = true;
  programs.zoxide.enable = true;
  programs.starship.enable = true;
  programs.direnv.enable = true;
  programs.carapace.enable = true;
  programs.carapace.enableNushellIntegration = true;
  programs.nushell.extraConfig = ''
    $env.CARAPACE_BRIDGES = "bash"
  '';
  xdg.configFile = {
    "carapace/specs/aws-sso.yaml".source = completionSpec "aws-sso" ''
      name: aws-sso
      description: Securely manage temporary AWS API credentials issued via AWS SSO
      persistentflags:
        -b, --browser=: Select the browser executable
        --config=: Select the configuration file
        -h, --help: Show help
        -L, --level=: Set the logging level
        --lines: Include line numbers in logs
        -S, --sso=: Select an AWS SSO instance
      commands:
        - name: ecs
          description: Manage the ECS credential server
          commands:
            - name: server
            - name: docker
            - name: list
            - name: unload
            - name: profile
            - name: load
        - name: list
          description: List accounts and roles
          flags:
            -f, --list-fields: List available fields
            --csv: Generate CSV output
            -P, --prefix=: Filter by field prefix
            -s, --sort=: Select the sort field
            --reverse: Reverse the sort order
        - name: login
          description: Log in to AWS Identity Center
        - name: setup
          description: Configure AWS SSO CLI
          commands:
            - name: completions
            - name: wizard
            - name: profiles
            - name: ecs
        - name: tags
          flags:
            -A, --account=: Filter by AWS account ID
            -R, --role=: Filter by role name
        - name: time
        - name: version
        - name: cache
        - name: console
        - name: credentials
        - name: eval
        - name: exec
        - name: logout
        - name: process
    '';
    "carapace/specs/git-lfs.yaml".source = completionSpec "git-lfs" ''
      name: git-lfs
      description: Git extension for versioning large files
      parsing: disabled
      completion:
        positionalany: ["$carapace.bridge.Cobra([git-lfs])"]
    '';
    "carapace/specs/krew.yaml".source = completionSpec "krew" ''
      name: krew
      description: Kubectl plugin manager
      parsing: disabled
      completion:
        positionalany: ["$carapace.bridge.Cobra([krew])"]
    '';
    "carapace/specs/kubectx.yaml".source = completionSpec "kubectx" ''
      name: kubectx
      description: Switch between Kubernetes contexts
      flags:
        -c, --current: Show the current context
        -d=: Delete a context
        -h, --help: Show help
        -r, --readonly=: Start a read-only shell scoped to a context
        -s, --shell=: Start a shell scoped to a context
        -u, --unset: Unset the current context
        -V, --version: Show version
      completion:
        flag:
          d: ["$carapace.tools.kubectl.Contexts"]
          readonly: ["$carapace.tools.kubectl.Contexts"]
          shell: ["$carapace.tools.kubectl.Contexts"]
        positionalany: ["$carapace.tools.kubectl.Contexts"]
    '';
    "carapace/specs/kubens.yaml".source = completionSpec "kubens" ''
      name: kubens
      description: Switch between Kubernetes namespaces
      flags:
        -c, --current: Show the current namespace
        -f, --force: Switch even when the namespace does not exist
        -h, --help: Show help
        -u, --unset: Unset the namespace
        -V, --version: Show version
      completion:
        positionalany: ["$carapace.tools.kubectl.NamespaceServiceAccounts"]
    '';
    "carapace/specs/opencode.yaml".source = completionSpec "opencode" ''
      name: opencode
      description: AI coding agent
      persistentflags:
        -h, --help: Show help
        -v, --version: Show version
        --print-logs: Print logs to stderr
        --log-level=: Set the log level
        --pure: Run without external plugins
      flags:
        --agent=: Select an agent
        --auto: Auto-approve permissions that are not denied
        -c, --continue: Continue the last session
        --cors*=: Add an allowed CORS origin
        --fork: Fork the selected session
        --hostname=: Set the server hostname
        -m, --model=: Select a provider/model
        --port=: Set the server port
        --prompt=: Set the prompt
        -s, --session=: Continue a session by ID
      completion:
        positionalany: ["$directories"]
      commands:
        - name: completion
          description: Generate shell completions
        - name: acp
          description: Start an ACP server
        - name: mcp
          description: Manage MCP servers
          commands:
            - name: add
            - name: list
            - name: auth
            - name: logout
            - name: debug
        - name: attach
          description: Attach to a running OpenCode server
        - name: run
          description: Run OpenCode with a message
        - name: debug
          description: Debugging and troubleshooting tools
          commands:
            - name: config
            - name: lsp
            - name: rg
            - name: file
            - name: skill
            - name: snapshot
            - name: startup
            - name: agent
            - name: info
            - name: paths
        - name: providers
          description: Manage providers and credentials
          commands:
            - name: list
            - name: login
            - name: logout
        - name: agent
          description: Manage agents
          commands:
            - name: create
            - name: list
        - name: upgrade
        - name: uninstall
        - name: serve
        - name: web
        - name: models
        - name: stats
        - name: export
        - name: import
          completion:
            positionalany: ["$files([.json])"]
        - name: github
          commands:
            - name: install
            - name: run
        - name: pr
        - name: session
          commands:
            - name: list
            - name: delete
        - name: plugin
        - name: db
          commands:
            - name: path
    '';
    "carapace/specs/tilt.yaml".source = completionSpec "tilt" ''
      name: tilt
      description: Local Kubernetes development environment
      persistentflags:
        -d, --debug: Enable debug logging
        -h, --help: Show help
        --klog=: Set Kubernetes API logging verbosity
        -v, --verbose: Enable verbose logging
      commands:
        - name: alpha
          description: Unstable and advanced commands
        - name: analytics
        - name: api-resources
        - name: apply
          flags:
            -f, --filename*=: Select configuration files
            -k, --kustomize=: Select a kustomization directory
            -R, --recursive: Process directories recursively
        - name: args
        - name: ci
          flags:
            --context=: Override the Kubernetes context
            -f, --file=: Select the Tiltfile
            --namespace=: Override the Kubernetes namespace
            --timeout=: Set the CI timeout
        - name: completion
          commands:
            - name: bash
            - name: fish
            - name: powershell
            - name: zsh
        - name: create
        - name: delete
        - name: demo
        - name: describe
        - name: disable
        - name: docker
        - name: docker-prune
        - name: doctor
        - name: down
        - name: dump
        - name: edit
        - name: enable
        - name: explain
        - name: get
        - name: help
        - name: logs
          flags:
            -f, --follow: Stream logs
            --json: Emit JSON Lines
            --level=: Select a log level
            --since=: Show logs since a duration ago
            --source=: Select a log source
            --tail=: Set the number of lines
        - name: lsp
        - name: patch
        - name: snapshot
          commands:
            - name: create
            - name: view
        - name: trigger
        - name: up
          flags:
            --context=: Override the Kubernetes context
            -f, --file=: Select the Tiltfile
            --namespace=: Override the Kubernetes namespace
            --stream: Stream logs in the terminal
            --update-mode=: Select the update strategy
        - name: verify-install
        - name: version
        - name: wait
    '';
    "carapace/specs/cheat.yaml".source = completionSpec "cheat" ''
      name: cheat
      description: Create and view interactive command-line cheatsheets
      flags:
        -a, --all: Search all cheatpaths
        -c, --colorize: Colorize output
        --conf: Display the config file path
        -d, --directories: List cheatsheet directories
        -e, --edit=: Edit a cheatsheet
        --init: Write a default config to stdout
        -l, --list: List cheatsheets
        -p, --path=: Select a cheatpath
        -r, --regex: Treat the search phrase as a regular expression
        --rm=: Remove a cheatsheet
        -s, --search=: Search cheatsheets
        -t, --tag=: Filter by tag
        -T, --tags: List tags
        -v, --version: Show version
    '';
    "carapace/specs/claude.yaml".source = completionSpec "claude" ''
      name: claude
      description: Claude Code
      flags:
        --add-dir=: Add directories to the allowed tool-access set
        --agent=: Select an agent
        --allowed-tools=: Set allowed tools
        --append-system-prompt=: Append to the system prompt
        --bare: Start with minimal integrations
        -c, --continue: Continue the most recent session
        -d, --debug=: Enable debug mode
        --dangerously-skip-permissions: Bypass permission checks
        --disallowed-tools=: Set disallowed tools
        --effort=: Set the effort level
        --fallback-model=: Select a fallback model
        -h, --help: Show help
        --input-format=: Set the input format
        --json-schema=: Validate structured output against a JSON schema
        --mcp-config=: Load MCP configuration
        --model=: Select a model
        --output-format=: Set the output format
        -p, --print: Print a response and exit
        -r, --resume=: Resume a session
        --safe-mode: Disable user customizations
        --settings=: Load settings from a file or JSON
        --system-prompt=: Replace the system prompt
        --verbose: Enable verbose output
        -v, --version: Show version
        -w, --worktree=: Start in a Git worktree
      commands:
        - name: agents
        - name: auth
        - name: auto-mode
        - name: doctor
        - name: gateway
        - name: install
        - name: mcp
        - name: plugin
        - name: project
        - name: setup-token
        - name: ultrareview
        - name: update
    '';
    "carapace/specs/jtc.yaml".source = completionSpec "jtc" ''
      name: jtc
      description: JSON transformation chains
      flags:
        -J: Wrap all processed JSON values into an array
        -a: Process all JSON values from the source
        -d: Enable debugging
        -f: Apply changes to the input file
        -g: Show the walk-path guide
        -h: Show help
        -j: Wrap walked elements into an array
        -l: Print labels for walked JSON values
        -n: Do not interleave walked output
        -p: Purge walked JSON elements
        -q: Enforce strict quoted-solidus parsing
        -r: Print compact JSON
        -s: Swap JSON elements selected by walk paths
        -z: Print the JSON node count
        -T=: Apply a template
        -c=: Compare with JSON, a walk path, or a template
        -i=: Insert JSON, a walk path, or a template
        -t=: Set indentation
        -u=: Update using JSON, a walk path, or a template
        -w=: Apply a walk path
        -x=: Set the common walk-path prefix
        -y=: Set an individual partial walk path
      completion:
        positionalany: ["$files([.json])"]
    '';
    "carapace/specs/psql.yaml".source = completionSpec "psql" ''
      name: psql
      description: PostgreSQL interactive terminal
      flags:
        -c, --command=: Run one SQL command and exit
        -d, --dbname=: Select a database
        -f, --file=: Execute commands from a file
        -h, --host=: Select the database server
        -l, --list: List databases
        -o, --output=: Write query results to a file
        -p, --port=: Select the database server port
        -q, --quiet: Suppress non-query output
        -U, --username=: Select the database user
        -v, --set=: Set a psql variable
        -V, --version: Show version
        -W, --password: Force a password prompt
      completion:
        flag:
          file: ["$files"]
          output: ["$files"]
    '';
    "carapace/specs/createdb.yaml".source = completionSpec "createdb" ''
      name: createdb
      description: Create a PostgreSQL database
      flags:
        -D, --tablespace=: Set the default tablespace
        -e, --echo: Echo commands sent to the server
        -E, --encoding=: Set the database encoding
        -h, --host=: Select the database server
        -l, --locale=: Set the database locale
        -O, --owner=: Set the database owner
        -p, --port=: Select the database server port
        -T, --template=: Select the template database
        -U, --username=: Select the database user
        -V, --version: Show version
        -W, --password: Force a password prompt
    '';
    "carapace/specs/pg_dump.yaml".source = completionSpec "pg_dump" ''
      name: pg_dump
      description: Export a PostgreSQL database
      flags:
        -a, --data-only: Dump only data
        -c, --clean: Drop database objects before recreating them
        -C, --create: Include database creation commands
        -d, --dbname=: Select a database
        -f, --file=: Select the output file
        -F, --format=: Select the output format
        -h, --host=: Select the database server
        -j, --jobs=: Set the number of parallel jobs
        -n, --schema=: Select schemas to dump
        -p, --port=: Select the database server port
        -s, --schema-only: Dump only the schema
        -t, --table=: Select tables to dump
        -U, --username=: Select the database user
        -v, --verbose: Enable verbose output
        -V, --version: Show version
      completion:
        flag:
          file: ["$files"]
    '';
    "carapace/specs/pg_restore.yaml".source = completionSpec "pg_restore" ''
      name: pg_restore
      description: Restore a PostgreSQL database archive
      flags:
        -a, --data-only: Restore only data
        -c, --clean: Drop database objects before recreating them
        -C, --create: Create the target database
        -d, --dbname=: Select a database
        -f, --file=: Select the output file
        -F, --format=: Select the archive format
        -h, --host=: Select the database server
        -j, --jobs=: Set the number of parallel jobs
        -l, --list: List the archive contents
        -p, --port=: Select the database server port
        -s, --schema-only: Restore only the schema
        -t, --table=: Select tables to restore
        -U, --username=: Select the database user
        -v, --verbose: Enable verbose output
        -V, --version: Show version
      completion:
        flag:
          file: ["$files"]
        positionalany: ["$files"]
    '';
    "carapace/specs/pg_isready.yaml".source = completionSpec "pg_isready" ''
      name: pg_isready
      description: Check PostgreSQL server connectivity
      flags:
        -d, --dbname=: Select a database
        -h, --host=: Select the database server
        -p, --port=: Select the database server port
        -q, --quiet: Suppress status messages
        -t, --timeout=: Set the connection timeout
        -U, --username=: Select the database user
        -V, --version: Show version
    '';
    "carapace/specs/rtk.yaml".source = completionSpec "rtk" ''
      name: rtk
      description: Token-optimized CLI proxy
      commands:
        - name: ls
        - name: tree
        - name: read
        - name: smart
        - name: git
        - name: gh
        - name: aws
        - name: psql
        - name: test
        - name: json
        - name: deps
        - name: env
        - name: find
        - name: diff
        - name: log
        - name: docker
        - name: kubectl
        - name: grep
        - name: rg
        - name: init
        - name: gain
        - name: config
        - name: cargo
        - name: npm
        - name: npx
        - name: curl
        - name: go
        - name: hook
        - name: help
    '';
    "carapace/specs/twg.yaml".source = completionSpec "twg" ''
      name: twg
      description: Atlassian Teamwork Graph CLI
      commands:
        - name: access
        - name: admin
        - name: api
        - name: assets
        - name: auth
        - name: benchmark
        - name: bitbucket
        - name: cache
        - name: capabilities
        - name: collaborators
        - name: confluence
        - name: consent
        - name: context
        - name: csm
        - name: doctor
        - name: docs
        - name: feedback
        - name: focus-areas
        - name: goals
        - name: help
        - name: jira
        - name: jsm
        - name: login
        - name: logout
        - name: loom
        - name: meetings
        - name: people
        - name: projects
        - name: pull-requests
        - name: resolve
        - name: responsibility
        - name: rovo
        - name: search-code
        - name: setup
        - name: skills
        - name: spaces
        - name: subgraph
        - name: talent
        - name: teams
        - name: trello
        - name: uninstall
        - name: upkeep
        - name: update
        - name: user
        - name: videos
        - name: visualize
        - name: whoami
        - name: work
    '';
  };
  programs.broot.enable = true;
  programs.atuin.enable = true;
  programs.difftastic = {
    enable = true;
    git = {
      enable = true;
      mode = "external";
    };
  };
  programs.lazygit = {
    enable = true;
    settings.git.diffRenderers = [
      {
        type = "extDiff";
        command = "${pkgs.difftastic}/bin/difft --color=always --context={{diffContext}}";
      }
    ];
  };
}
