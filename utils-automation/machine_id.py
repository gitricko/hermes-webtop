import platform
import subprocess
import uuid
import os

def get_machine_id():
    """
    Returns a unique, stable hardware identifier for the current machine/VM.
    OS agnostic: supports macOS, Linux, and Windows.
    Falls back to MAC address if deeper hardware UUIDs are unavailable.
    """
    try:
        if platform.system() == "Darwin":
            output = subprocess.check_output(["ioreg", "-rd1", "-c", "IOPlatformExpertDevice"]).decode('utf-8')
            for line in output.split('\n'):
                if 'IOPlatformUUID' in line:
                    return line.split('"')[3]
        elif platform.system() == "Linux":
            if os.path.exists("/etc/machine-id"):
                with open("/etc/machine-id", "r") as f:
                    return f.read().strip()
            elif os.path.exists("/var/lib/dbus/machine-id"):
                with open("/var/lib/dbus/machine-id", "r") as f:
                    return f.read().strip()
        elif platform.system() == "Windows":
            import winreg
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Cryptography") as key:
                return winreg.QueryValueEx(key, "MachineGuid")[0]
    except Exception:
        pass
    
    # Ultimate fallback: The MAC address of the network interface
    return str(uuid.getnode())
