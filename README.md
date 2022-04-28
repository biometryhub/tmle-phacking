# tmle-phacking
Code/VM setup for Max's Targeted Maximum Likelihood Estimation p-hacking paper.

## How to run a TMLE simulation (on a OCI/AWS/GCP virtual machine)
1. Specify the `cloud-init.yaml` file when provisioning the cloud VM, which will automatically install Docker and the ancillary system libraries, pull this git repository, and set up R v4.X and the necessary libraries all upon first run.
2. `ssh` into the machine and quickly confirm that everything worked (either review the log at `/var/log/cloud-init-output.log`, or quickly check by running `sudo docker image list` to ensure that the `tmle-phacking` Docker image exists and was created successfully).
3. Run the shell script `tmle-phacking/run_N.sh`, specifying the input size N (`-n`) and the number of random seeds (`-s`), e.g.
```
cd tmle-phacking
./run_N.sh -n 100 -s 10000
```
4. Done! The script runs the Docker container with R and the code files inside a nohup and logs output already, so there is no need to do anything further. Simply wait for the job to finish. Once finished, the outputs can be pulled from the cloud VMs using `sftp`, etc.
