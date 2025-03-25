## Switch Backup Automation Script

### Overview
This PowerShell script automates backing up running configurations from network switches via their REST APIs, complete with robust logging, error handling, and email notifications. It's structured into clearly defined phases for clarity and easy maintenance.

---

### Phases

### ✅ **Phase 0: Initialization**
- Loads external functions:
  - Credential management (`CredentialFunction.ps1`)
  - Email sending (`EmailFunctions.ps1`)
  - Logging (`LogWriteFunctions.ps1`)
- Defines paths to configuration files for SMTP (email alerts) and encrypted credentials.
- Sets encryption key path, API version, and log directories.

### ✅ **Phase 1: Credential Loading**
- Loads primary (Radius-based) and alternate (Local) encrypted credentials securely.
- Ensures necessary directories exist for outputs and logs.
- Sets SSL certificate validation bypass (useful for switches with self-signed certificates).

### ✅ **Phase 2: Import Switch List**
- Imports switches from a CSV file containing hostnames and IP addresses.
  - **Note:** The CSV is optional. It can easily be replaced by defining an array of IP addresses or hostnames directly within the script, especially useful when managing a small or static list of switches.

### ✅ **Phase 3: Switch Configuration Backup**
For each switch listed:
1. Attempts REST API login with primary credentials.
   - Falls back to alternate credentials if primary login fails.
2. Fetches the running configuration via REST API.
3. Saves the running configuration locally with a timestamped filename.
4. Logs detailed statuses, including any errors encountered.
5. Logs out from the switch API session.

### ✅ **Phase 4: Summary Compilation**
- Summarizes total processed switches, successes, and failures.
- Generates a detailed breakdown of successful and failed backups by hostname and IP.

### ✅ **Phase 5: Email Notification**
- Sends a comprehensive summary via SMTP email to administrators, providing immediate awareness of backup results.

### ✅ **Phase 6: Script Completion**
- Logs final script completion status clearly:
  - Indicates overall success if all switches processed successfully.
  - Indicates errors occurred if one or more switches failed.

---

### 📄 Configuration File Details *(for reference)*

The configuration XML file (`switchbackup-accountconfig.xml`) structure includes:

```xml
<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">
  <Obj RefId="0">
    <TN RefId="0">
      <T>Deserialized.System.Management.Automation.PSCustomObject</T>
      <T>Deserialized.System.Object</T>
    </TN>
    <MS>
      <S N="Username">placeholder</S>
      <S N="Password">placeholder=</S>
      <S N="AltUsername">placeholder</S>
      <S N="AltPassword">placeholder=</S>
      <S N="Input">\\placeholder\ConfigBackup_Switch\Import\Switches.csv</S>
      <S N="Output">\\placeholder\Switches</S>
    </MS>
  </Obj>
</Objs>
```

- **`Username`/`Password`:** Primary (Radius) credentials.
- **`AltUsername`/`AltPassword`:** Secondary (Local) fallback credentials.
- **`Input`:** Path to switches CSV file.
- **`Output`:** Directory where backups are stored.

---

This setup provides a flexible, secure, and easily maintained approach for automated configuration backups, suitable for networks of varying complexity.

