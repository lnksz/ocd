---
name: ansible
description: Develop, validate, and run Ansible playbooks and roles. Install missing Ansible, ansible-lint, and the Ansible language server on demand inside a verified container only.
---

# Ansible on demand

The default agent images include this skill without the Ansible tools. Reuse
working project tools first. For missing tools, run this read-only check using
the skill's actual directory if it differs from the image path:

```bash
bash /usr/local/share/agent-skills/ansible/scripts/install.sh --check
```

If it fails, do not run installation, sudo, package managers, `npx`, or `uvx`
on the host. Use the project's container workflow and repeat the check inside
it. A VM, WSL, generic `container-other` sandbox, environment variable, or Docker
socket alone does not verify the container boundary. Do not bypass the guard.

After a successful check, install only if the task needs missing tools:

```bash
bash /usr/local/share/agent-skills/ansible/scripts/install.sh --install
ansible --version
ansible-lint --version
ansible-language-server --version
```

The installer repeats the guard before passwordless sudo. It pins Ansible
14.5.0, ansible-lint 26.10.0, and the language server 26.6.0, using isolated pipx
environments under `/opt/ansible-tools` and commands in `/usr/local/bin`.
Downloads and installation caches stay inside the container and are removed
after setup. It does not edit mounted host configuration. Installation persists
only as long as that container does; it never runs at image build or startup.
Existing unmanaged installations are left for inspection and reuse.

Use the project's inventory, `ansible.cfg`, collection requirements, and lint
configuration. Install additional collections only when the task needs them and
only after the container check, choosing a container-local collection directory
unless the user asks to change project files. Validate changed playbooks with
`ansible-lint` and `ansible-playbook --syntax-check` against the intended inventory.
Scope any execution to the targets and changes authorized by the user; installing
the tools does not authorize a deployment. Use `--check --diff` when appropriate,
keeping secrets out of output. Check mode can still run tasks that opt out of it.

Installation follows the upstream [Ansible pipx guidance](https://docs.ansible.com/projects/ansible/latest/installation_guide/intro_installation.html#installing-and-upgrading-ansible-with-pipx),
including `--include-deps` so that `ansible` and `ansible-playbook` are exposed.
