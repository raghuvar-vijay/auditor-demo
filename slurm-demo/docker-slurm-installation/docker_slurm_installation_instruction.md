### Installing docker 

Follow the steps to install docker for almalinux9

1. Set up the repository
```
sudo dnf install -y dnf-utils
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
```

2. Install Docker engine

```
sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

3. Start and enable docker

```
sudo systemctl start docker
sudo systemctl enable docker
```

4. Post installation steps:
To run docker commands as a non-root user 

```
sudo usermod -aG docker $USER
```


### Install slurm as docker

Please clone the github repo `https://github.com/ALU-Schumacher/auditor-demo`

```
git clone https://github.com/ALU-Schumacher/auditor-demo
```


You can navigate to slurm-demo folder which contains the scripts to start a slurm batch system in a docker container.

```
cd slurm-demo
```

You start the slurm docker using this bash script

```
./auditor_demo_slurm.sh
```

It might take couple of minutes to pull the docker image and start the slurm container

You would see this at the end of successful execution

```
Slurmctld(primary) at slurmctl is UP
```

You can check the status of the docker container

```
docker ps
```

And should see the container up and running. Something just like this

```
34253d888d5c   giovtorres/docker-centos7-slurm:latest   "/tini -- /usr/local…"   24 hours ago   Up 6 minutes          0.0.0.0:9000->9000/tcp, [::]:9000->9000/tcp   auditor-slurm-1
```


We need to start the slurm collector in the slurm container. 

```
docker exec -it auditor-slurm-1 bash
```

This command lets you execute commands inside the running container.

We have already provided the slurm collector binary and the config file in the container.

You can change the collector_config file by executing 

```
[root@slurmctl /]#  vim collector_config.yaml
```

I have used the example from the AUDITOR documentation


```
addr: "host.docker.internal"
port: 8000
record_prefix: "slurm"
job_filter:
  status:  # A list of acceptable job statuses
    - "completed"
sacct_frequency: 2 # in seconds
sender_frequency: 1 # in seconds
sites:
  - name: "site_id_1"
    only_if:
      key: "Partition"
      matches: "^part1$"
  - name: "site_id_2"
    only_if:
      key: "Partition"
      matches: "^part2$"
meta:
  - name: Comment
    key: "Comment"
    key_type: Json
components:
  - name: "Cores"
    key: "NCPUS"
    scores:
      - name: "hepspec23"
        value: 10
        only_if:
          key: "Partition"
          matches: "^part1$"
      - name: "hepspec23"
        value: 12
        only_if:
          key: "Partition"
          matches: "^part2$"
  - name: "SystemCPU"
    key: "SystemCPU"
    key_type: Time
    only_if:
      key: "Partition"
      matches: "^part1$"
  - name: "UserCPU"
    key: "UserCPU"
    key_type: Time
    only_if:
      key: "Partition"
      matches: "^part1$"
  - name: "Memory"
    key: "ReqMem"
    key_type: IntegerMega
tls_config:
  use_tls: false
```

Now, we can run the slurm collector using the command:

```
[root@slurmctl /]# ./auditor-slurm-collector /collector_config.yaml
```

In a new terminal, you have to execute the bash script to insert the test jobs.

We can submit some test jobs to slurm container using the `insert_mock_jobs.sh`. You can find this in the slurm-demo folder. This script will submit 20 test jobs to slurm.

```
./insert_mock_jobs.sh
```

You can see in the logs of slurm collector in docker that the records are being processed and sent to AUDITOR.


