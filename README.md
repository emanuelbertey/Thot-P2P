# Aplicación de Comunicación P2P con Godot 4.4  
# P2P Communication App with Godot 4.4  

## Thot-P2P  

### Descripción / Description
Esta aplicación permite la comunicación **P2P (Peer-to-Peer)** entre dispositivos utilizando diferentes métodos en Godot 4.4: **ENet, WebSocket, TCP, UDP, libp2p y nostr**.  
Su objetivo principal es conectar dispositivos y facilitar el intercambio de información, datos o mensajes.  

This application enables **Peer-to-Peer (P2P)** communication between devices using different methods in Godot 4.4: **ENet, WebSocket, TCP, UDP, libp2p, and nostr**.  
Its main goal is to connect devices and facilitate the exchange of information, data, or messages.  

---

### Características / Features
- **Conexiones P2P**: Soporte para ENet, WebSocket, WebRTC, TCP, UDP y en beta libp2p, torrent y nostr.  
- **Intercambio de Información**: Permite enviar y recibir mensajes entre dos dispositivos conectados.  
- **Implementación Modular**: Cada método de conexión está implementado como un módulo independiente.  

- **P2P Connections**: Support for ENet, WebSocket, WebRTC, TCP, UDP, and in beta libp2p, torrent, and nostr.  
- **Information Exchange**: Allows sending and receiving messages between two connected devices.  
- **Modular Implementation**: Each connection method is implemented as an independent module.  

---

### Requisitos / Requirements
- Godot Engine 4.4 o superior.  
- Conexión a Internet y/o localhost, IPv4/IPv6.  
- Dos dispositivos compatibles con Godot.  

- Godot Engine 4.4 or higher.  
- Internet connection and/or localhost, IPv4/IPv6.  
- Two devices compatible with Godot.  

---

## Métodos de Conexión / Connection Methods

### ENet
ENet es una biblioteca confiable para comunicación en tiempo real.  
Ideal para juegos en línea, chats en tiempo real y transferencia de archivos pequeños.  

ENet is a reliable networking library for real-time communication.  
Ideal for online games, real-time chats, and small file transfers.  

### WebSocket y WebRTC / WebSocket and WebRTC
Proporcionan comunicación bidireccional sobre una sola conexión TCP.  
Perfecto para aplicaciones web interactivas, juegos multijugador en navegador e IoT.  

Provide bidirectional communication over a single TCP connection.  
Perfect for interactive web apps, browser-based multiplayer games, and IoT.  

### TCP y UDP / TCP and UDP
TCP es confiable y sencillo de implementar.  
Usado en transferencia de archivos, administración remota y sistemas distribuidos.  

TCP is reliable and easy to implement.  
Used in file transfers, remote administration, and distributed systems.  

---

## Usos Útiles / Useful Use Cases
1. **Juegos Multijugador / Multiplayer Games**  
2. **Aplicaciones de Chat / Chat Applications**  
3. **Colaboración en Tiempo Real / Real-Time Collaboration**  
4. **Intercambio de Archivos / File Sharing**  
5. **Control Remoto / Remote Control**  

---

## Contribuir / Contributing
¡Las contribuciones son bienvenidas! Haz un fork, crea una rama y envía un pull request.  

Contributions are welcome! Fork the repository, create a branch, and submit a pull request.  

---

## Licencia / License
Este proyecto está bajo la **Licencia MIT**. Consulta el archivo `LICENSE`.  

This project is licensed under the **MIT License**. See the `LICENSE` file for details.  
