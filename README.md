# Prime Agent - Rootless Docker

---

This repository aims to share an isolated Prime Agent running inside a rootless Docker container.

Rootless Docker is the first filter; Docker's engine is run by a user daemon not thru the system-wide one.

Prime Agent has its own IAM. It can run everything it needs with its own accesses but is bounded to its container if it tries to escape.

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
  --add-host host.docker.internal:host-gateway \
  <image_name>:<tag>
```

To reach an external AI provider, run:

```
docker run -d --name <container-name> \
  -v prime-home:/home/agent \
  -v prime-workspace:/workspace \
  --network <my-custom-network> \
  <image_name><:tag>
```

> **N.B.: \<container-name> litterally the name you choose to give to the container. It can be pretty much anything.**

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
# on the host, inside your local clone (one-time setup)
git config protocol.ext.allow always
git remote add agent "ext::docker exec -i -u agent prime-agent %S /workspace/myproject"

git fetch agent            # retrieve the agent's commits
git diff main agent/main   # review them
git merge agent/main       # accept them
git push agent main        # send your changes to the agent
```

`%S` is replaced by `git-upload-pack` or `git-receive-pack`, which run inside the container as `agent`. All it requires is git in the image, which we have anyway.

* **Setup:** two commands per project.
* **Day to day:** you use plain `git fetch` and `git push`.
* **Review:** you check the agent's work before merging it, which fits the README's "review changes" advice.

One detail: to `git push` onto the branch the agent has checked out, we'll set `receive.denyCurrentBranch updateInstead` in the container repo, or simply push to a different branch.

#######
