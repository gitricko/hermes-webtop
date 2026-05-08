#!/usr/bin/env python3
import getpass
from pathlib import Path
import hashlib
import base64
from machine_id import get_machine_id

def xor_crypt(data, key):
    machine_salt = get_machine_id()
    combined_key = f"{key.lower()}::{machine_salt}"
    key_hash = hashlib.sha256(combined_key.encode()).digest()
    crypted = bytearray()
    for i, char in enumerate(data):
        crypted.append(char ^ key_hash[i % len(key_hash)])
    return crypted

def main():
    print("🔐 Password Encryption Utility for Hermes Automation")
    email = input("Enter your Google Email (used as encryption key): ").strip()
    
    if not email or "@" not in email:
        print("❌ Invalid email format.")
        return
        
    pwd = getpass.getpass("Enter your Google Password: ")
    
    if not pwd:
        print("❌ Password cannot be empty.")
        return
    
    # Encrypt
    crypted_bytes = xor_crypt(pwd.encode(), email)
    enc_str = base64.b64encode(crypted_bytes).decode('utf-8')
    
    # Save
    out_file = Path.home() / ".google-oauth-automation" / "password.enc"
    out_file.parent.mkdir(parents=True, exist_ok=True)
    out_file.write_text(enc_str)
    
    print(f"✅ Encrypted password saved to {out_file}")
    print("   🔒 Note: This encryption is salted with this machine's Hardware ID.")
    print("      If this .enc file is moved to another computer, decryption will likely produce an invalid value rather than the original password.")

if __name__ == "__main__":
    main()
