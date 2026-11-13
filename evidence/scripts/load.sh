cd ~/pse-support-lab
sleep 20
out=evidence/02-load-sampler.txt
: > $out
( for i in $(seq 1 60); do
    echo "$(date -u +%T) $(docker stats --no-stream --format '{{.MemUsage}}' invoicely-lite-api-1 2>&1) restarts=$(docker inspect invoicely-lite-api-1 --format '{{.RestartCount}} oom={{.State.OOMKilled}} exit={{.State.ExitCode}}' 2>&1)" >> $out
    sleep 5
  done ) &
make load 2>&1 | tee evidence/02-make-load-output.txt | tail -40
wait
