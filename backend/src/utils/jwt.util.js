import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';

export const generateAccessToken = (payload) =>
  jwt.sign(payload, env.JWT.ACCESS_SECRET, { expiresIn: env.JWT.ACCESS_EXPIRES_IN });

export const generateRefreshToken = (payload) =>
  jwt.sign(payload, env.JWT.REFRESH_SECRET, { expiresIn: env.JWT.REFRESH_EXPIRES_IN });

export const verifyAccessToken = (token) =>
  jwt.verify(token, env.JWT.ACCESS_SECRET);

export const verifyRefreshToken = (token) =>
  jwt.verify(token, env.JWT.REFRESH_SECRET);
