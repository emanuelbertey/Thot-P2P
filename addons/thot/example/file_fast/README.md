# File Fast (Iroh P2P)

This is a Godot example for bidirectional file transfer using **Iroh**.

## Features

- **Chunked Transfer**: Large files are split into 64KB chunks to ensure smooth transfer over the peer-to-peer connection.
- **Hash Verification**: After a file is received, its SHA-256 hash is compared with the sender's hash to ensure data integrity.
- **Offer/Accept Protocol**: Peers can offer a list of files. the receiver selects exactly which files they want to download.
- **Custom Save Location**: The receiver chooses the directory where files will be saved.
- **Bidirectional**: Both peers can send and receive files simultaneously.

## How to use

1. **Start the App**: Open the `file_fast.tscn` scene in Godot.
2. **Connect**:
   - One peer clicks **Host (Get Ticket)** and copies the generated ticket.
   - The other peer pastes the ticket into the input field and clicks **Join Peer**.
3. **Send Files**:
   - Click **Add Files** to select one or more files from your disk.
   - Click **Send Offer to Peers** to notify the other peer about the files you want to share.
4. **Receive Files**:
   - The other peer will see the incoming offer on their screen.
   - Click **Download** next to a file.
   - Select a folder to save the file.
   - The transfer starts immediately!

## Technical Details

- **Protocol**: Uses Godot's High-Level Multiplayer API (RPCs) over Iroh's secure P2P transport.
- **Verification**: Uses `FileAccess.get_sha256()` for end-to-end integrity checks.
