import React, { useEffect } from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from 'react-query';
import * as Sentry from '@sentry/react';
import './App.css';
import Dashboard from './components/Dashboard';
import Login from './components/Login';
import HealthCheck from './components/HealthCheck';
import PrivateRoute from './components/PrivateRoute';

// Initialize Sentry for error tracking
if (process.env.REACT_APP_SENTRY_DSN) {
  Sentry.init({
    dsn: process.env.REACT_APP_SENTRY_DSN,
    environment: process.env.REACT_APP_ENVIRONMENT || 'development',
    tracesSampleRate: 1.0,
  });
}

// Initialize React Query client
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 3,
      staleTime: 5 * 60 * 1000, // 5 minutes
      cacheTime: 10 * 60 * 1000, // 10 minutes
      refetchOnWindowFocus: false,
    },
  },
});

const App: React.FC = () => {
  useEffect(() => {
    // Report web vitals
    if (process.env.REACT_APP_ENABLE_ANALYTICS === 'true') {
      import('web-vitals').then(({ getCLS, getFID, getFCP, getLCP, getTTFB }) => {
        getCLS(console.log);
        getFID(console.log);
        getFCP(console.log);
        getLCP(console.log);
        getTTFB(console.log);
      });
    }
  }, []);

  return (
    <Sentry.ErrorBoundary fallback={<ErrorFallback />}>
      <QueryClientProvider client={queryClient}>
        <Router>
          <div className="App">
            <Routes>
              <Route path="/login" element={<Login />} />
              <Route path="/health" element={<HealthCheck />} />
              <Route
                path="/dashboard"
                element={
                  <PrivateRoute>
                    <Dashboard />
                  </PrivateRoute>
                }
              />
              <Route
                path="/"
                element={
                  <PrivateRoute>
                    <Dashboard />
                  </PrivateRoute>
                }
              />
            </Routes>
          </div>
        </Router>
      </QueryClientProvider>
    </Sentry.ErrorBoundary>
  );
};

const ErrorFallback: React.FC = () => {
  return (
    <div className="error-fallback">
      <h2>Oops! Something went wrong</h2>
      <p>We're sorry for the inconvenience. Please refresh the page or try again later.</p>
      <button onClick={() => window.location.reload()}>Refresh Page</button>
    </div>
  );
};

export default App;
