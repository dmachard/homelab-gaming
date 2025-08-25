#!/usr/bin/env python3
import subprocess
import json
import base64
import time
import sys
import argparse

def check_vm_status(vm_name):
    """Check VM state and QEMU agent availability"""
    try:
        cmd = ["virsh", "domstate", vm_name]
        output = subprocess.check_output(cmd, stderr=subprocess.PIPE)
        state = output.decode().strip()
        return state
    except subprocess.CalledProcessError as e:
        print(f"Error checking VM state: {e} - status: failed")
        return False

def start_vm(vm_name):
    """Start the VM if it's not running"""
    print(f"Starting VM {vm_name}...")
    try:
        cmd = ["virsh", "start", vm_name]
        subprocess.check_output(cmd, stderr=subprocess.PIPE)
        print(f"VM {vm_name} started - status: success")

        print("Waiting for VM to be ready...")
        for i in range(60):
            try:
                test_cmd = {"execute": "guest-ping"}
                virsh_qemu_agent_command(vm_name, test_cmd)
                print("QEMU agent available - status: ready")
                return True
            except:
                time.sleep(2)

        print("VM started but QEMU agent not responding - status: degraded")
        return False

    except subprocess.CalledProcessError as e:
        print(f"Error starting VM: {e} - status: failed")
        return False

def shutdown_vm(vm_name):
    """Gracefully shutdown the VM"""
    print("Shutting down VM...")
    try:
        try:
            shutdown_cmd = {
                "execute": "guest-shutdown",
                "arguments": {"mode": "powerdown"}
            }
            virsh_qemu_agent_command(vm_name, shutdown_cmd)
            print("Shutdown command sent to VM via QEMU agent - status: success")
        except Exception:
            pass

        print("Waiting for VM shutdown...")
        for i in range(60):
            try:
                cmd = ["virsh", "domstate", vm_name]
                output = subprocess.check_output(cmd, stderr=subprocess.PIPE)
                state = output.decode().strip()
                if state == "shut off":
                    print("VM shutdown successfully - status: success")
                    return True
                time.sleep(1)
            except:
                pass

        print("Graceful shutdown failed, forcing shutdown... - status: warning")
        cmd = ["virsh", "destroy", vm_name]
        subprocess.check_output(cmd, stderr=subprocess.PIPE)
        print("VM forcefully shutdown - status: success")
        return True

    except Exception as e:
        print(f"Error shutting down VM: {e} - status: failed")
        return False

def wait_for_agent(vm_name):
    """Wait for QEMU agent to be available"""
    print("Waiting for QEMU agent...")
    for i in range(30):
        try:
            test_cmd = {"execute": "guest-ping"}
            virsh_qemu_agent_command(vm_name, test_cmd)
            print("QEMU agent available - status: ready")
            return True
        except:
            time.sleep(2)
    print("QEMU agent not available - status: failed")
    return False

def virsh_qemu_agent_command(vm, command_dict):
    cmd = ["virsh", "qemu-agent-command", vm, json.dumps(command_dict)]
    try:
        output = subprocess.check_output(cmd, stderr=subprocess.PIPE)
        return json.loads(output)
    except subprocess.CalledProcessError as e:
        print(f"Command failed: {e} - status: failed", file=sys.stderr)
        if e.output:
            print(e.output.decode(), file=sys.stderr)
        raise

def run_powershell(vm, ps_command):
    exec_command = {
        "execute": "guest-exec",
        "arguments": {
            "path": "powershell.exe",
            "arg": ["-Command", ps_command],
            "capture-output": True
        }
    }
    result = virsh_qemu_agent_command(vm, exec_command)
    pid = result["return"]["pid"]

    while True:
        status_cmd = {
            "execute": "guest-exec-status",
            "arguments": {"pid": pid}
        }
        status = virsh_qemu_agent_command(vm, status_cmd)
        if status["return"]["exited"]:
            break
        time.sleep(0.2)

    out_data = status["return"].get("out-data")
    if out_data:
        return base64.b64decode(out_data).decode(errors='ignore').strip()
    else:
        return ""

def get_gpu_info(vm_name):
    """Get GPU instance ID and status"""
    #print("Searching for Radeon GPU device...")

    ps_get_instance = (
        "Get-PnpDevice | Where-Object { $_.FriendlyName -like '*Radeon*' } | "
        "Select-Object -ExpandProperty InstanceId"
    )
    instance_id = run_powershell(vm_name, ps_get_instance).splitlines()
    instance_id = instance_id[0].strip() if instance_id else ""

    if not instance_id:
     #   print("No Radeon GPU device found - status: failed")
        return None, None

    #print(f"Found InstanceId: {instance_id} - status: success")

    ps_get_status = f"Get-PnpDevice -InstanceId '{instance_id}' | Select-Object -ExpandProperty Status"
    status = run_powershell(vm_name, ps_get_status).splitlines()
    status = status[0].strip() if status else ""

    #print(f"Current GPU status: {status}")
    return instance_id, status

def enable_gpu(vm_name, instance_id):
    """Enable the GPU device"""
    print("Enabling the GPU...")
    ps_enable = f"pnputil /enable-device \"{instance_id}\""
    run_powershell(vm_name, ps_enable)
    print("GPU enabled - status: success")

    print("Starting Looking Glass...")
    try:
        run_powershell(vm_name, "Start-Service -Name \"Looking Glass (host)\"")
        print("Looking Glass started - status: success")
    except Exception as e:
        print(f"Could not start Looking Glass: {e} - status: warning")

def disable_gpu(vm_name, instance_id):
    """Disable the GPU device"""
    print("Disabling the GPU...")
    ps_disable = f"pnputil /disable-device \"{instance_id}\""
    run_powershell(vm_name, ps_disable)
    print("GPU disabled - status: success")

def start_action(vm_name):
    """Start VM with GPU enabled"""
    print("Starting VM with GPU enabled...")

    initial_state = check_vm_status(vm_name)
    if initial_state is None:
        print("Cannot determine VM state - status: failed")
        sys.exit(1)

    print(f"Initial VM state: {initial_state}")

    if initial_state == "shut off":
        if not start_vm(vm_name):
            print("Failed to start VM - status: failed")
            sys.exit(1)
    elif initial_state != "running":
        print(f"VM is in unexpected state: {initial_state} - status: failed")
        sys.exit(1)

    if not wait_for_agent(vm_name):
        print("Cannot continue without QEMU agent - status: failed")
        sys.exit(1)

    instance_id, status = get_gpu_info(vm_name)
    if not instance_id:
        sys.exit(1)

    if status != "OK":
        enable_gpu(vm_name, instance_id)
    else:
        print("GPU is already enabled - status: ok")

    print("VM started successfully with GPU enabled - status: success")

def stop_action(vm_name):
    """Stop VM with GPU disabled"""
    print("Stopping VM with GPU disabled...")

    initial_state = check_vm_status(vm_name)
    if initial_state is None:
        print("Cannot determine VM state - status: failed")
        sys.exit(1)

    if initial_state == "shut off":
        print("VM is already stopped - status: ok")
        return
    elif initial_state != "running":
        print(f"VM is in unexpected state: {initial_state} - status: failed")
        sys.exit(1)

    if not wait_for_agent(vm_name):
        print("Cannot continue without QEMU agent - status: failed")
        sys.exit(1)

    instance_id, status = get_gpu_info(vm_name)
    if not instance_id:
        sys.exit(1)

    if status == "OK":
        disable_gpu(vm_name, instance_id)
    else:
        print("GPU is already disabled - status: ok")

    if shutdown_vm(vm_name):
        print("VM stopped successfully - status: success")
    else:
        print("Failed to stop VM properly - status: failed")
        sys.exit(1)

def status_action(vm_name):
    """Display VM, QEMU agent, GPU, and Looking Glass status"""
    print("Checking VM status...")

    state = check_vm_status(vm_name)
    print(f"VM state: {state}")

    # Check GPU
    instance_id, status = get_gpu_info(vm_name)
    if not instance_id:
        print("GPU: Not found")
    else:
        gpu_status = "enabled" if status == "OK" else "disabled"
        print(f"GPU: Found ({gpu_status})")

    # Check Looking Glass service
    try:
        ps_check_service = (
            "Get-Service -Name \"Looking Glass (host)\" | "
            "Select-Object -ExpandProperty Status"
        )
        service_status = run_powershell(vm_name, ps_check_service).lower()
        if "running" in service_status:
            print("Looking Glass: running")
        elif "stopped" in service_status:
            print("Looking Glass: stopped")
        else:
            print(f"Looking Glass: {service_status}")
    except Exception:
        print("Looking Glass: unknown")

def send_key_sequence(vm_name, keys):
    """Send key sequence to VM using QEMU monitor"""
    print(f"Sending key sequence: {keys}")
    try:
        cmd = ["virsh", "qemu-monitor-command", vm_name, "--hmp", f"sendkey {keys}"]
        subprocess.check_output(cmd, stderr=subprocess.PIPE)
        print(f"Key sequence sent successfully - status: success")
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error sending key sequence: {e} - status: failed")
        return False

def send_ctrl_alt_del(vm_name):
    """Send Ctrl+Alt+Delete to VM"""
    print("Sending Ctrl+Alt+Delete to VM...")

    # Vérifier que la VM est en cours d'exécution
    state = check_vm_status(vm_name)
    if state != "running":
        print(f"VM is not running (state: {state}) - status: failed")
        return False

    # Envoyer la séquence Ctrl+Alt+Delete
    return send_key_sequence(vm_name, "ctrl-alt-delete")

def audio_action(vm_name):
    """Send Ctrl+Alt+Delete to VM"""
    print("Sending Ctrl+Alt+Delete to VM...")

    # Vérifier que la VM est en cours d'exécution
    state = check_vm_status(vm_name)
    if state != "running":
        print(f"VM is not running (state: {state}) - status: failed")
        return False

    # Envoyer la séquence Ctrl+Alt+Delete
    return send_key_sequence(vm_name, "ctrl-shift-q")

def main():
    try:
        parser = argparse.ArgumentParser(
            description="VM GPU Manager - Manage GPU state in Windows VMs",
            formatter_class=argparse.RawDescriptionHelpFormatter,
            epilog="""
Examples:
  %(prog)s start --vm-name myvm      # Start VM with GPU enabled
  %(prog)s stop --vm-name myvm       # Stop VM with GPU disabled
  %(prog)s status --vm-name myvm     # Show VM status
  %(prog)s ctrl-alt-del --vm-name myvm   # Send Ctrl+Alt+Delete
  %(prog)s switch-audio --vm-name myvm  # Switch between HD Audio and AMD Audio
            """
        )

        parser.add_argument(
            "action",
            choices=["start", "stop", "ctrl-alt-del", "status", "switch-audio"],
            help="Action to perform"
        )

        parser.add_argument(
            "--vm-name",
            required=True,
            help="VM name"
        )

        args = parser.parse_args()

        if args.action == "start":
            start_action(args.vm_name)
        elif args.action == "stop":
            stop_action(args.vm_name)
        elif args.action == "status":
            status_action(args.vm_name)
        elif args.action == "ctrl-alt-del":
            send_ctrl_alt_del(args.vm_name)
        elif args.action == "switch-audio":
            audio_action(args.vm_name)
        else:
            sys.exit(1)

    except Exception as e:
        print(f"Fatal error: {e} - status: failed")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()
