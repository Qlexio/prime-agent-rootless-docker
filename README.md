# Prime Agent - Unsloth

---

## Unsloth

---

Run command:

```
unsloth run \
  --model unsloth/granite-4.1-3b-GGUF:UD-Q8_K_XL \
  -H 0.0.0.0 \
  -p 8888 \
  --disable-tools
```

## Prime Agent - Docker

---

### Build Prime Agent Docker image

```
cd path/to/repo
docker build -t <image_name>:<tag> .
```

### Required volumes

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

### Run container

```
docker run -d --name prime-agent \
  -v prime-home:/home/agent \
  -v prime-workspace:/workspace \
  --add-host host.docker.internal:host-gateway \
  <image_name>:<tag>
```

### Helpful commands

```
docker logs -f prime-agent                          # watch the first-launch install
docker exec -it prime-agent bash                    # look around
docker exec -it prime-agent <prime-agent command>   # start the agent
```

### Models configuration

Inside the container, add a `~/.prime/agent/models.json` file with the following:

```
{
  "providers": {
    "unsloth-studio": {
      "baseUrl": "http://<unsloth_server_ip>:<unsloth_server_port>/v1",
      "api": "openai-completions",
      "apiKey": "sk-unsloth-YOUR_KEY",
      "compat": {
        "supportsDeveloperRole": false,
        "supportsReasoningEffort": false,
        "supportsUsageInStreaming": false
      },
      "models": [
        {
          "id": "unsloth/granite-4.1-3b-GGUF:UD-Q8_K_XL",
          "name": "My_local_LLM",
          "input": ["text"],
          "contextWindow": 16384,
          "maxTokens": 4096,
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
        }
      ]
    }
  }
}
```

> ⚠️ N.B.: `id` must match the served model exactly.

> N.B.: `"name"` is the model ame displayed by `/model` command.

> ⚠️ N.B.: `"contextWindow"` must be the exact same value than  `--max-seq-length` if parameter passed to the server.

### Chat completion test

Run:

```
docker exec -it prime-agent curl http://<unsloth_server_ip>:<unsloth_server_port>/v1/chat/completions \
    -H "Authorization: Bearer sk-unsloth-YOUR_KEY" \
    -H "Content-Type: application/json" \
    -d '{"messages": [{"role": "user", "content": "Hello"}], "stream": true}'
```

> ⚠️ N.B.: Provide the exact same `model` than the one provided at container launch.


### Update Prime Agent

To update the OS inside the container, run:

```
docker exec -u root prime-agent apt update && apt upgrade
```

> ⚠️ N.B.: Those changes disappear when the container is recreated. Rebuilding the image remains the durable path.

To update **`Prime Agent`**, run:

```
docker exec prime-agent prime-agent update 
```

To display **`Prime Agent`** version:

```
docker exec prime-agent prime-agent --version
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
