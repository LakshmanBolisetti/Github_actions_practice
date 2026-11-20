# Create Cluster Objects by Using Imperative Commands

## Challenge Overview

You are a DevOps Engineer at Hexelo. In this challenge, you will create and manage Kubernetes objects by using imperative `kubectl` commands.

You will:

1. Create standalone pods using `kubectl run`.
2. Create a Deployment using `kubectl create deployment`.
3. Scale the Deployment using `kubectl scale`.
4. Retrieve pod, event, log, label, node, and application information.
5. Verify the NGINX web server using `curl`.
6. Delete the pods and Deployment from the `default` namespace.
7. Save command outputs to report files under `/home/administrator/`.

> **Environment:** The lab automatically signs you in to the Windows Server 2019 (WS2019) desktop as Administrator. The Kubernetes master node is `k8s-master1`; worker nodes are `k8s-worker1` and `k8s-worker2`. Run all Kubernetes commands from the master node using `kubectl`.

---

## 1. Connect to the Kubernetes Master Node

1. Open **MobaXterm**.
2. In the sidebar, under **User sessions**, double-click `k8s-master1`.
3. When prompted, enter the password:

   ```text
   Passw0rd!
   ```

4. Press **Enter**. The password will not be visible while typing.
5. If prompted to save the password, select **No**.

All commands below should be run in the SSH terminal on `k8s-master1`.

---

## 2. Create Pods Using Imperative Commands

### 2.1 Create pod1 with the NGINX image

Create a pod named `pod1` using the `nginx` image:

```bash
kubectl run pod1 --image=nginx
```

The `kubectl run` command creates the pod directly. The `--image` option specifies the container image.

### 2.2 Check the status of pod1

```bash
kubectl get pods pod1
```

Run the command again and save the output to `/home/administrator/pod1-report.txt`:

```bash
kubectl get pods pod1 > /home/administrator/pod1-report.txt
```

### 2.3 Create pod2 with the Redis image and a label

Create a pod named `pod2` using the `redis` image and add the label `tier=database`:

```bash
kubectl run pod2 --image=redis --labels=tier=database
```

Labels help organize and select Kubernetes resources. They do not change the pod's behavior.

### 2.4 Display both pods

```bash
kubectl get pods
```

If either pod shows `ContainerCreating`, wait a few moments and run the command again:

```bash
kubectl get pods
```

Save the pod list to `/home/administrator/pods-report.txt`:

```bash
kubectl get pods > /home/administrator/pods-report.txt
```

> **Note:** A pod created directly with `kubectl run` is a standalone pod. Unlike a pod managed by a Deployment, it does not have a controller that automatically recreates it if it fails.

### Checkpoint

- [ ] `pod1` exists and uses the `nginx` image.
- [ ] `pod2` exists and uses the `redis` image.
- [ ] `pod2` has the label `tier=database`.
- [ ] You displayed the pods and saved both requested reports.

---

## 3. Create a Deployment Using an Imperative Command

### 3.1 Create the apache Deployment

Create a Deployment named `apache` using the `httpd` image:

```bash
kubectl create deployment apache --image=httpd
```

A Deployment manages replicated pods. It can maintain the desired number of replicas, support rolling updates, and help recover pods if they fail.

### 3.2 Display the pods

```bash
kubectl get pods
```

### 3.3 Display the Deployments

```bash
kubectl get deployments
```

Save the Deployment list to `/home/administrator/deployment-report.txt`:

```bash
kubectl get deployments > /home/administrator/deployment-report.txt
```

### 3.4 Scale the apache Deployment to three replicas

```bash
kubectl scale deployment --replicas=3 apache
```

This sets the desired number of `apache` pods to three.

### 3.5 Verify the Deployment scaling

```bash
kubectl get deployments
```

Save the output to `/home/administrator/deployment-apatch-scale.txt`:

```bash
kubectl get deployments > /home/administrator/deployment-apatch-scale.txt
```

> **Filename note:** The report filename above intentionally preserves the lab's spelling: `deployment-apatch-scale.txt`.

### 3.6 Display and save the pods after scaling

```bash
kubectl get pods
```

Save the output to `/home/administrator/pods-report-scale.txt`:

```bash
kubectl get pods > /home/administrator/pods-report-scale.txt
```

You should see three pods managed by the `apache` Deployment, in addition to `pod1` and `pod2`.

### Checkpoint

- [ ] The `apache` Deployment exists.
- [ ] The Deployment uses the `httpd` image.
- [ ] The Deployment has three replicas.
- [ ] You displayed and saved the Deployment and pod reports.

---

## 4. Retrieve Pod and Cluster Information

### 4.1 Retrieve Kubernetes events

```bash
kubectl get events
```

Events provide information about cluster activity, such as pod scheduling, image pulling, and container creation.

Save the event output to `/home/administrator/event-logs.txt`:

```bash
kubectl get events > /home/administrator/event-logs.txt
```

### 4.2 Retrieve logs from pod2

```bash
kubectl logs pod2
```

This displays the container logs for `pod2`.

### 4.3 Display pods with the database label

```bash
kubectl get pods -l tier=database
```

The `-l` option filters Kubernetes resources by label. In this case, it selects pods with `tier=database`.

Save the output to `/home/administrator/pods-label-report.txt`:

```bash
kubectl get pods -l tier=database > /home/administrator/pods-label-report.txt
```

### 4.4 Display pod IP addresses and node names

```bash
kubectl get pods -o wide
```

The `-o wide` option displays additional details, including pod IP addresses and the nodes on which the pods are running.

Save the output to `/home/administrator/pods-wide-report.txt`:

```bash
kubectl get pods -o wide > /home/administrator/pods-wide-report.txt
```

Find the `pod1` row in the output and note its **IP** value. Enter that IP address in the lab's **IP Address** text box.

> **Important:** Use the actual IP address displayed by your cluster. Pod IP addresses can differ between lab environments.

### 4.5 Verify the NGINX web server using curl

Run the following command, replacing `<POD1_IP>` with the actual IP address of `pod1`:

```bash
curl -I http://<POD1_IP>
```

For example, if the IP shown for `pod1` were `10.244.1.5`, the command would be:

```bash
curl -I http://10.244.1.5
```

The `-I` option requests and displays the HTTP response headers. A response such as the following indicates that the web server answered the request:

```text
HTTP/1.1 200 OK
Server: nginx
```

Save the command output to `/home/administrator/pod1-nginx.txt`:

```bash
curl -I http://<POD1_IP> > /home/administrator/pod1-nginx.txt
```

Replace `<POD1_IP>` with the same actual IP address.

> **Troubleshooting:** If the request does not succeed, check that `pod1` is `Running`, confirm its IP using `kubectl get pods -o wide`, and retry. The pod must be reachable from the machine where you run `curl`.

### Checkpoint

- [ ] You retrieved Kubernetes events and saved the event report.
- [ ] You retrieved logs from `pod2`.
- [ ] You displayed and saved pods matching `tier=database`.
- [ ] You identified pod IP addresses and node names and saved the wide report.
- [ ] You entered the actual IP address of `pod1` in the lab.
- [ ] You verified the NGINX web server using `curl -I` and saved the response.

---

## 5. Delete Pods and the Deployment

> **Important:** Delete the Deployment itself rather than deleting only its pods. A Deployment manages its replicas and will recreate pods that are deleted while the Deployment still exists.

### 5.1 Display the pods before deletion

```bash
kubectl get pods
```

### 5.2 Delete pod1

```bash
kubectl delete pod pod1
```

### 5.3 Delete pod2

```bash
kubectl delete pod pod2
```

### 5.4 Delete the apache Deployment

```bash
kubectl delete deployment apache
```

Deleting the Deployment also removes the ReplicaSet and the pods managed by it.

### 5.5 Verify that no pods remain in the default namespace

```bash
kubectl get pods
```

The lab should report that no resources were found in the `default` namespace:

```text
No resources found in default namespace.
```

Save the output to `/home/administrator/deletion-report.txt`:

```bash
kubectl get pods > /home/administrator/deletion-report.txt
```

> **Note:** The command output is redirected to the report file. If you also want to see the output in the terminal while saving it, use:
>
> ```bash
> kubectl get pods | tee /home/administrator/deletion-report.txt
> ```

### Final Checkpoint

- [ ] `pod1` has been deleted.
- [ ] `pod2` has been deleted.
- [ ] The `apache` Deployment has been deleted.
- [ ] No pods remain in the default namespace.
- [ ] The deletion report has been saved.

---

## 6. Summary of All Report Files

The challenge asks you to save command output to the following files:

| Report file | Command / purpose |
|---|---|
| `/home/administrator/pod1-report.txt` | Status of `pod1` |
| `/home/administrator/pods-report.txt` | Pod list after creating `pod1` and `pod2` |
| `/home/administrator/deployment-report.txt` | Deployment list after creating `apache` |
| `/home/administrator/deployment-apatch-scale.txt` | Deployment list after scaling `apache` |
| `/home/administrator/pods-report-scale.txt` | Pod list after scaling `apache` |
| `/home/administrator/event-logs.txt` | Kubernetes events |
| `/home/administrator/pods-label-report.txt` | Pods with label `tier=database` |
| `/home/administrator/pods-wide-report.txt` | Pod IP addresses and node names |
| `/home/administrator/pod1-nginx.txt` | HTTP response headers from NGINX |
| `/home/administrator/deletion-report.txt` | Pod list after cleanup |

To check that the report files exist:

```bash
ls -l /home/administrator/*report*.txt /home/administrator/event-logs.txt /home/administrator/pod1-nginx.txt
```

---

## 7. Important kubectl Commands Reference

| Command | Purpose |
|---|---|
| `kubectl run` | Create a pod imperatively |
| `kubectl create deployment` | Create a Deployment imperatively |
| `kubectl get pods` | List pods |
| `kubectl get deployments` | List Deployments |
| `kubectl scale` | Change the number of Deployment replicas |
| `kubectl get events` | Display cluster events |
| `kubectl logs` | Display container logs |
| `kubectl get pods -l` | Filter pods by label |
| `kubectl get pods -o wide` | Display additional pod details |
| `kubectl delete pod` | Delete a pod |
| `kubectl delete deployment` | Delete a Deployment and its managed resources |
| `curl -I` | Display HTTP response headers |

## 8. Imperative vs. Declarative Management

**Imperative management** tells Kubernetes exactly what action to perform using commands such as:

```bash
kubectl run pod1 --image=nginx
kubectl scale deployment apache --replicas=3
kubectl delete pod pod1
```

**Declarative management** uses configuration files, commonly YAML, to describe the desired state of resources. You apply the configuration with:

```bash
kubectl apply -f deployment.yaml
```

| Imperative | Declarative |
|---|---|
| Specifies an action to perform | Specifies the desired resource state |
| Uses direct commands | Uses YAML or JSON configuration files |
| Useful for quick tasks and troubleshooting | Useful for repeatable and version-controlled deployments |
| Command history alone is not a complete resource configuration | Configuration can be stored in Git and reviewed |

> **Best practice:** Imperative commands are useful for learning, quick operations, and troubleshooting. For production workloads, declarative configuration managed through version control is generally preferred.

---

## Challenge Completed

You have created standalone pods, created and scaled a Deployment, inspected cluster and pod information, verified the NGINX web server, saved the required reports, and cleaned up all application resources in the default namespace.
