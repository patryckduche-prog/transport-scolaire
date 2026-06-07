import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { buildCoachNavigation } from '../services/coach-navigation.service.js';

const router = Router();

router.use(requireAuth(['driver', 'company', 'region']));

router.get('/coach-route/:routeId', async (req, res) => {
  const navigation = await buildCoachNavigation(req.params.routeId);
  if (!navigation) return res.status(404).json({ error: 'coach_route_not_found' });
  res.json(navigation);
});

export default router;
