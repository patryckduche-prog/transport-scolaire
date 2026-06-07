import { WebSocketServer } from 'ws';

const clients = new Set();

export function attachRealtime(server) {
  const wss = new WebSocketServer({ server, path: '/ws' });
  wss.on('connection', (socket) => {
    clients.add(socket);
    socket.send(JSON.stringify({ type: 'connected', at: new Date().toISOString() }));
    socket.on('close', () => clients.delete(socket));
    socket.on('error', () => clients.delete(socket));
  });
  return wss;
}

export function broadcastRealtime(event) {
  const payload = JSON.stringify({ ...event, at: new Date().toISOString() });
  for (const socket of clients) {
    if (socket.readyState === 1) socket.send(payload);
  }
}
