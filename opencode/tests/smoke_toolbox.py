#!/usr/bin/env python3
"""Check the lean toolbox and optionally install Ansible in a disposable container."""
import argparse
import subprocess

DEFAULT_CHECKS = r'''
set -euo pipefail
for removed in hunk hunkdiff ansible ansible-playbook ansible-lint ansible-language-server; do
    if command -v "$removed" >/dev/null; then
        printf 'Unexpected default tool: %s\n' "$removed" >&2
        exit 1
    fi
done
ast-grep --version
printf 'console.log(42);\n' | ast-grep run --pattern 'console.log(42)' --lang javascript --stdin
printf 'function smoke() { return 42; }\n' > /tmp/outline-smoke.js
ast-grep outline /tmp/outline-smoke.js
for skill in reverse-eng ansible; do
    test -f "/usr/local/share/agent-skills/$skill/SKILL.md"
    bash "/usr/local/share/agent-skills/$skill/scripts/install.sh" --check
done
'''

ANSIBLE_CHECKS = r'''
# Run the guarded installer as a regular container user, exercising sudo too.
useradd -m -u 7777 toolbox-smoke
sudo -n -u toolbox-smoke -- bash /usr/local/share/agent-skills/ansible/scripts/install.sh --install
sudo -n -u toolbox-smoke -- bash /usr/local/share/agent-skills/ansible/scripts/install.sh --install
cat > /home/toolbox-smoke/smoke.yml <<'PLAYBOOK'
---
- name: Validate the container toolbox
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Assert localhost execution
      ansible.builtin.assert:
        that:
          - inventory_hostname == 'localhost'
PLAYBOOK
chown toolbox-smoke:toolbox-smoke /home/toolbox-smoke/smoke.yml
sudo -n -u toolbox-smoke -H -- bash -c '
    set -euo pipefail
    cd "$HOME"
    ansible-playbook --syntax-check -i localhost, smoke.yml
    ansible-playbook --check -i localhost, smoke.yml
    ansible-lint --offline smoke.yml
    ansible-language-server --version
'
test -z "$(find /opt/ansible-tools -maxdepth 1 -name 'downloads.*' -print)"
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image")
    parser.add_argument("--install-ansible", action="store_true")
    args = parser.parse_args()
    script = DEFAULT_CHECKS + (ANSIBLE_CHECKS if args.install_ansible else "")
    subprocess.run(["docker", "run", "--rm", "-i", "--user", "0", "--entrypoint", "bash",
                    args.image, "-s"], input=script, text=True, check=True)


if __name__ == "__main__":
    main()
