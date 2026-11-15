# Prime Agent - Rootless Docker

---

This repository aims to share an isolated Prime Agent running inside a rootless Docker container.

Rootless Docker is the first filter; Docker's engine is run by a user daemon not thru the system-wide one.

Prime Agent has its own IAM. It can run everything it needs with its own accesses but is bounded to its container if it tries to escape.

It was made to easily connect to custom LLM servers; understand not builtin AI providers.

**Ollama**, **LLM Studio** and **vLLM** are natively supported.

**llama.cpp**(-based) servers seems to run well too.

Connection tests were made on:
* [Unsloth](https://unsloth.ai/docs)
* [Mammouth AI LLM provider](https://mammouth.ai)

## Docker's pre-requisites

### Build Prime Agent Docker image

```
cd path/to/repo
docker build -t <image_name>:<tag> .
```

### Required volumes

This docker image handles persistant memory locally stored, make sure to mount volumes.

| Volume              | Mount           | Contents                                                                                                                  |
| ------------------- | --------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `prime-home`      | `/home/agent` | Prime Agent binary, IPython runtime/venv, config, auth, sessions, Continual Harness state (memories, skills, refinements) |
| `prime-workspace` | `/workspace`  | Repositories the agent works on (cloned inside)                                                                           |

```
docker volume create prime-home
```

```
docker volume prime-workspace
```

### Docker network parameters

To reach an ***external web AI provider***, the **MTU** needs to be changed to **`1500`** max like newer Docker versions tend to set higher MTU.

```
$ docker network create \
  --driver=bridge \
  --opt com.docker.network.driver.mtu=1400 \
  <my-custom-net>
```

## Run container

To reach a locally hosted AI provider, run:

```
docker run -d --name <container-name> \
  -v prime-home:/home/agent \
  -v prime-workspace:/workspace \
  -e <MY_PROVIDER_API_KEY>=<$MY_PROVIDER_API_KEY> \
  --add-host host.docker.internal:host-gateway \
  <image_name>:<tag>
```

To reach an external AI provider, run:

```
docker run -d --name <container-name> \
  -v prime-home:/home/agent \
  -v prime-workspace:/workspace \
  -e <MY_PROVIDER_API_KEY>=<$MY_PROVIDER_API_KEY> \
  --network <my-custom-network> \
  <image_name><:tag>
```

> **N.B.: \<container-name> litterally the name you choose to give to the container. It can be pretty much anything.**

> **⚠️ N.B.: To set your *`API_KEY`* in a host environment variable:<\br>
>
> `$ export MY_PROVIDER_API_KEY="sk-..."`.<\br>
>
> MY_PROVIDER_API_KEY is not a fixed value as `prime-setup` will propose you to use a variable under this format:<\br>
>
> \<AI_PROVIDER_NAME>_API_KEY>

At first launch, Prime Agent is installed and a to be filled in *models.json* is copied to **`~/.prime/agent/models.json`**.

## Set up a custom AI provider (Recommended)

To easily set up a custom AI provider, either a local one or not, run:

```
docker exec -it <container-name> prime-setup
```

And answer to asked values to automatically fill in *`models.json`*.

> **Known limitation: `prime-setup` can be run multiple times to set up new LLM and/or AI providers.</br>To add a new LLM from the same provider, input another name; e.g. *`my-provider-2`*.`</br>`Otherwise, the previous configuration will be erased.`</br>`You can use the same *API KEY* and API endpoint.**

> ⚠️N.B.: *`prime-setup`* do not configure visualization yet. Simple add or replace **`image`** to **"input"** entry in `models.json`. Recent LLM can bypass a missing **`image`** by calling programmic tools like **Pillow**.

> ⚠️ N.B.: `id` must match the served model exactly.

> N.B.: `"name"` is the model ame displayed by `/model` command.

> ⚠️ N.B.: `"contextWindow"` must be the exact same value than  `--max-seq-length` if parameter passed to the server.

The complete list of `models.json` parameters in [pi.dev documentation](https://pi.dev/docs/latest/models-configuration).

## Helpful commands

```
docker logs -f <container-name>                          # watch the first-launch install
docker exec -it <container-name> bash                    # look around
docker exec -it <container-name> prime-agent <command>   # start the agent
```

## Chat completion test

Run:

```
docker exec <container-name> curl -X POST https://<server-ip:port>/v1/chat/completions \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4.1",
    "messages": [
      {
        "role": "user",
        "content": "Hello, world ?"
      }
    ]
  }'
```

> ⚠️ N.B.: Some AI provider requires the exact same `model` than the one provided at container launch.

## Update Prime Agent

To update the container OS, run:

```
docker exec -u root <container-name> apt update && apt upgrade
```

> ⚠️ N.B.: Those changes disappear when the container is recreated. Rebuilding the image remains the durable path.

To update **`Prime Agent`**, run:

```
docker exec <container-name> prime-agent update
```

To display **`Prime Agent`** version:

```
docker exec <container-name> prime-agent --version
```

## Prime Agent / User pair work

---

#######

#TODO Run, test and/or complete

**The git workflow:** the repo lives in the volume, and you sync with git **through `docker exec`**. There's no server, no exposed port and no permission juggling. Git's built-in `ext` transport does this:

```bash
# To git clone the agent Git project on your host:
git -c protocol.ext.allow=user clone \
  "ext::docker exec -i -u <container-user> <container-name> %S /path/to/agent-project" \
  <myproject>
```

```bash
# On the host, inside your local clone (one-time setup)
git config protocol.ext.allow user
git remote add agent "ext::docker exec -i -u <container-user> <container-name> %S /path/to/agent-project"

git fetch agent            # retrieve the agent's commits
git diff main agent/main   # review them
git merge agent/main       # accept them
git push agent main<:main> # send your changes to the agent; <:main> is the agent's branch name
```

`%S` is replaced by `git-upload-pack` or `git-receive-pack`, which run inside the container as `agent`. All it requires is git in the image, which we have anyway.

* **Setup:** two commands per project.
* **Day to day:** you use plain `git fetch` and `git push`.
* **Review:** you check the agent's work before merging it, which fits the README's "review changes" advice.

To push into the agent’s checked-out branch, set `receive.denyCurrentBranch=updateInstead` in the container repository. Git refuses the push if the agent’s worktree or index differs from `HEAD`.

```
docker exec -u <username> <docker-container> git -C <path/to/agent-project> config receive.denyCurrentBranch updateInstead
```

### Working with GitHub at the same time

The host clone is the hub. GitHub and the agent are just two remotes:

```bash
git remote -v
# origin  git@github.com:<username>/myproject.git   (fetch/push)
# agent   ext::docker exec -i -u <container-user> <container-name> %S /path/to/agent-project

git fetch agent && git merge agent/main   # bring in the agent's work
git push origin main                      # publish to GitHub
git push agent main                       # keep the agent up to date
```

**Nothing about the `ext` setup reaches GitHub.** Both `protocol.ext.allow` and the `agent` remote are stored in `.git/config`, which is local and never pushed. Git configuration and remote definitions are local to this clone; tracked files are shared only when you commit and push them. Pay attention to files likes `.gitmodules` which are shared and can be compromising.

If you'd rather not keep the setting at all, pass it per command instead:

```bash
git -c protocol.ext.allow=user fetch agent
git -c protocol.ext.allow=user push agent main
```

### Security considerations

**Why `ext` is disabled by default (CVE-2015-7545).** An `ext::` URL is an arbitrary shell command. Before Git 2.6.1, a malicious repository could put an `ext::` URL in its **`.gitmodules`** file, which is tracked and pushed like any other file. A victim running `git clone --recursive` or `git submodule update` would then execute the attacker's command. This is a *drive-by clone* / remote code execution attack. Git restricts dangerous protocols in non-user-initiated operations. In current Git, `ext` defaults to `never`; setting `protocol.ext.allow=user` permits direct use while keeping it disallowed for operations such as recursive submodule initialization.

**Use `user`, not `always`.**

* `always` allows `ext::` everywhere, **including URLs coming from submodules**. That reopens the CVE-2015-7545 attack surface.
* `user` allows `ext::` only for commands you type yourself, such as `git fetch agent`. Git blocks it when the URL comes from a submodule, so a malicious `.gitmodules` (from GitHub, a dependency, or the agent) cannot trigger it.

**Treat the agent's commits as untrusted input.**

* Always review `git diff main agent/main` before merging. Watch for changes to `.gitmodules`, CI workflows (`.github/workflows/`), build scripts (`Makefile`, `package.json` scripts / `postinstall`, `setup.py`), and dependency manifests or lockfiles.
* A compromised or misbehaving agent could add a typosquatted or malicious dependency. That would turn your project into the entry point of a **software supply chain attack** against everyone who uses it, once it's pushed to GitHub.
* A **normal** fetch does not transfer Git hooks or `.git/config` into the host clone., so the agent cannot plant hooks or remotes in your host clone.

**The remote URL is a command.** The `agent` remote runs `docker exec` on the host. Only add `ext::` remotes you wrote yourself, and never copy `ext::` URLs from untrusted sources.

#######