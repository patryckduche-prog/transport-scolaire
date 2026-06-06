import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';

export function requireAuth(roles = []) {
  return (req, res, next) => {
    const header = req.headers.authorization ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) return res.status(401).json({ error: 'missing_token' });
    try {
      req.user = jwt.verify(token, env.jwtSecret);
      if (roles.length > 0 && !roles.includes(req.user.role)) return res.status(403).json({ error: 'forbidden' });
      next();
    } catch {
      res.status(401).json({ error: 'invalid_token' });
    }
  };
}
