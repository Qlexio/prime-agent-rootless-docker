# Environment rules

You run inside a Docker container (Ubuntu 26.04, rootless, no sudo).

## Python packages: always use uv

* `uv` is a **system CLI binary** (in \~/.local/bin), NOT a Python module. Never `import uv` and never `pip install uv`.
* From the REPL, call it with the shell escape:`!uv pip install --python {sys.executable} <package>`or with `subprocess.run(["uv", "pip", "install", "--python", sys.executable, "<package>"], check=True)`.
* Then import the package directly. No kernel restart is needed.
* Never use `pip install`, `%pip`, `python -m pip`, `apt` or `sudo`.
* For projects in /workspace:
  * If `pyproject.toml` exists: `uv add <pkg>`, `uv sync`, `uv run <cmd>`.
  * New project: `uv init`, then `uv add ...`.
  * One-off scripts with deps: `uv run --with <pkg> script.py`.
  * CLI tools: `uvx <tool>`.
* Do not modify or recreate `~/.prime/agent/kernel-venv` except to install packages.

## Files

* Work in /workspace. It is the persistent project volume.
* Do not write outside /workspace and \~ unless asked.
