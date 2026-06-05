# FUSE Validation Runbook

## Goal

Validate whether a remote storage endpoint can be mounted inside the lab as a FUSE-backed filesystem, then determine whether the same pattern survives inside an OpenShell sandbox.

## Current status

As of 2026-06-05, the lab has already produced a concrete result:

1. Plain privileged Pod on `runc` baseline: `sshfs` mount works
2. OpenShell sandbox with default base image: not enough, because the image does not include `sshfs` / `fusermount3`
3. OpenShell sandbox with a custom `amd64` image that includes FUSE tooling: still not enough, because the sandbox cannot reach the SSH endpoint used in this lab

Read the latest result here:

- [testing/openshell-fuse-validation-2026-06-05.md](/Users/hwchiu/hwchiu/openqq/testing/openshell-fuse-validation-2026-06-05.md)

## Recommended strategy

Do **not** start with OpenShell directly.

Use two stages:

1. Plain privileged Kubernetes pod
2. OpenShell sandbox on the known-good `runc` baseline

This splits failures cleanly:

- If stage 1 fails, the problem is FUSE / node / container runtime
- If stage 1 passes and stage 2 fails, the problem is OpenShell bootstrap, policy, or sandbox isolation

## Why `runc` first

The current repo evidence already shows:

1. `runc + OpenShell` is the only fully working path
2. `gVisor + OpenShell` loses filesystem enforcement
3. `Kata + OpenShell` is blocked earlier by `privileged` incompatibility

For a filesystem-heavy experiment like FUSE, `runc` is the only sensible first target.

## Baseline profile

Use the cheaper Terraform profile:

```bash
make tf-apply-fuse
./scripts/fetch-kubeconfig.sh
make fuse-prereq
```

This profile uses:

- `vm_size = "Standard_B2s"`
- `container_runtime = "containerd"`

## Stage 1: Plain pod baseline

Apply:

```bash
kubectl --kubeconfig generated/kubeconfig apply -f k8s/fuse-ssh-server.yaml
kubectl --kubeconfig generated/kubeconfig -n fuse-lab rollout status deploy/sshfs-server
kubectl --kubeconfig generated/kubeconfig apply -f k8s/fuse-sshfs-baseline.yaml
kubectl --kubeconfig generated/kubeconfig -n fuse-lab logs -f pod/sshfs-baseline
```

Success criteria:

1. `/dev/fuse` exists in the pod
2. `sshfs` mount succeeds
3. `ls /mnt/remote` shows remote content
4. `mount | grep /mnt/remote` shows a FUSE mount
5. `fusermount3 -u` cleanly unmounts

## Stage 2: OpenShell sandbox

After the plain pod works, repeat the same idea inside an OpenShell sandbox.

The main design question is **which remote protocol to use**.

### Option A: `sshfs`

Pros:

1. easy to reason about
2. directly proves generic remote-FS mounting

Cons:

1. OpenShell network policy is currently demonstrated mainly with HTTP/REST rules
2. SSH-based allow rules need a dedicated policy design pass

### Option B: `rclone mount` to WebDAV / S3-like HTTPS target

Pros:

1. aligns better with OpenShell's demonstrated HTTP/REST policy path
2. easier to explain in the current lab

Cons:

1. slightly more moving parts than `sshfs`

## My recommendation

For this repo, the most practical order is:

1. Prove FUSE generally works with `sshfs` in a plain pod
2. For OpenShell, prefer an HTTPS-backed FUSE client such as `rclone mount`

That path is more likely to coexist with OpenShell's current network controls.

This recommendation is now evidence-backed, not just a guess:

1. `sshfs` itself works on the cluster
2. OpenShell sandbox can expose `/dev/fuse` and helper binaries when given a custom image
3. But the current sandbox network path still failed against SSH/TCP endpoints in this lab

## Expected blockers inside OpenShell

1. `privileged: true` is still required for the current Kubernetes driver path
2. the sandbox image may not have `sshfs` / `rclone` / `fuse3` preinstalled
3. `filesystem_policy` must allow the mountpoint path and helper binaries
4. network policy must allow the remote endpoint
5. some FUSE helpers expect `/dev/fuse`, `fusermount3`, and `SYS_ADMIN`

## What to capture

When you run the first real FUSE pass, save:

1. `ls -l /dev/fuse`
2. `mount | grep fuse`
3. `dmesg | tail`
4. pod `describe`
5. pod logs

That evidence will tell us very quickly whether the failure is:

1. missing device
2. missing capability
3. denied mount syscall
4. denied egress
5. denied helper binary
