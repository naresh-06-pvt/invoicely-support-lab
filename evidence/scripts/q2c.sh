cd ~/pse-support-lab
{
docker run --rm --privileged --pid=host alpine sh -c 'dmesg | grep -iE "oom|killed process|memory cgroup" | tail -12' 2>&1
echo ---
docker inspect invoicely-lite-api-1 --format 'memlimit={{.HostConfig.Memory}} memswap={{.HostConfig.MemorySwap}} restartpolicy={{.HostConfig.RestartPolicy.Name}}'
} | tee evidence/02-dmesg-oom.txt
