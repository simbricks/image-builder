#!/bin/bash -eux
#
# SimBricks guest payload runner (orchestration plumbing, not user software.
# Orchestration attaches the per-experiment payload as a
# second disk (/dev/sdb); this installs the hook that untars it and runs
# guest/run.sh. Kept identical to the old repo so the protocol does not change.

set -eux

install -m0755 /dev/stdin /home/ubuntu/guestinit.sh <<'EOF'
#!/bin/sh
cd /tmp
tar xf /dev/sdb
cd guest
./run.sh
EOF
chown ubuntu:ubuntu /home/ubuntu/guestinit.sh
