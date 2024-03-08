#!/usr/bin/env -S julia --color=no --startup-file=no

using K8sDeputy

deputy = Deputy()
server = K8sDeputy.serve!(deputy, "0.0.0.0")
graceful_terminator(() -> shutdown!(deputy))
readied!(deputy)
wait(server)
