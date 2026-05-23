import { Routes, Route, Navigate } from 'react-router-dom';
import { useAuthStore } from '@/store/auth.store.js';
import LoginPage from '@/pages/LoginPage.jsx';
import RegisterPage from '@/pages/RegisterPage.jsx';
import DashboardPage from '@/pages/DashboardPage.jsx';
import StoragePage from '@/pages/StoragePage.jsx';
import AccountPage from '@/pages/AccountPage.jsx';
import Layout from '@/components/Layout.jsx';

const PrivateRoute = ({ children }) => {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  const accessToken = useAuthStore((s) => s.accessToken);
  const refreshToken = useAuthStore((s) => s.refreshToken);
  const isGuest = useAuthStore((s) => s.isGuest);
  return (isAuthenticated && (accessToken || refreshToken)) || isGuest ? children : <Navigate to="/login" replace />;
};

const AuthenticatedRoute = ({ children }) => {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  const accessToken = useAuthStore((s) => s.accessToken);
  const refreshToken = useAuthStore((s) => s.refreshToken);
  return isAuthenticated && (accessToken || refreshToken) ? children : <Navigate to="/login" replace />;
};

const PublicRoute = ({ children }) => {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  const accessToken = useAuthStore((s) => s.accessToken);
  const refreshToken = useAuthStore((s) => s.refreshToken);
  return !(isAuthenticated && (accessToken || refreshToken)) ? children : <Navigate to="/dashboard" replace />;
};

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<PublicRoute><LoginPage /></PublicRoute>} />
      <Route path="/register" element={<PublicRoute><RegisterPage /></PublicRoute>} />
      <Route path="/" element={<PrivateRoute><Layout /></PrivateRoute>}>
        <Route index element={<Navigate to="/dashboard" replace />} />
        <Route path="dashboard" element={<DashboardPage />} />
        <Route path="storage" element={<StoragePage />} />
        <Route path="account" element={<AuthenticatedRoute><AccountPage /></AuthenticatedRoute>} />
        <Route path="chat" element={<Navigate to="/dashboard" replace />} />
        <Route path="chat/:id" element={<Navigate to="/dashboard" replace />} />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}
