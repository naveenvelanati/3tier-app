import axios, { AxiosInstance, AxiosRequestConfig, AxiosResponse, AxiosError } from 'axios';
import * as Sentry from '@sentry/react';

const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:8000';
const API_TIMEOUT = 30000; // 30 seconds

// Create axios instance with default config
const apiClient: AxiosInstance = axios.create({
  baseURL: API_BASE_URL,
  timeout: API_TIMEOUT,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Request interceptor - Add auth token
apiClient.interceptors.request.use(
  (config: any) => {
    const token = localStorage.getItem('auth_token');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    
    // Add request ID for tracing
    config.headers['X-Request-ID'] = generateRequestId();
    
    return config;
  },
  (error: AxiosError) => {
    Sentry.captureException(error);
    return Promise.reject(error);
  }
);

// Response interceptor - Handle errors
apiClient.interceptors.response.use(
  (response: AxiosResponse) => {
    return response;
  },
  async (error: AxiosError) => {
    const originalRequest: any = error.config;
    
    // Handle 401 Unauthorized - Refresh token
    if (error.response?.status === 401 && !originalRequest._retry) {
      originalRequest._retry = true;
      
      try {
        const refreshToken = localStorage.getItem('refresh_token');
        const response = await axios.post(`${API_BASE_URL}/auth/refresh`, {
          refresh_token: refreshToken,
        });
        
        const { access_token } = response.data;
        localStorage.setItem('auth_token', access_token);
        
        originalRequest.headers.Authorization = `Bearer ${access_token}`;
        return apiClient(originalRequest);
      } catch (refreshError) {
        // Refresh failed, redirect to login
        localStorage.removeItem('auth_token');
        localStorage.removeItem('refresh_token');
        window.location.href = '/login';
        return Promise.reject(refreshError);
      }
    }
    
    // Handle 429 Too Many Requests - Retry with exponential backoff
    if (error.response?.status === 429 && !originalRequest._retryCount) {
      originalRequest._retryCount = 1;
      const retryAfter = parseInt(error.response.headers['retry-after'] || '5', 10);
      
      await new Promise(resolve => setTimeout(resolve, retryAfter * 1000));
      return apiClient(originalRequest);
    }
    
    // Log error to Sentry
    Sentry.captureException(error, {
      extra: {
        url: error.config?.url,
        method: error.config?.method,
        status: error.response?.status,
      },
    });
    
    return Promise.reject(error);
  }
);

// API Service Functions
export const apiService = {
  // Health Check
  healthCheck: async (): Promise<any> => {
    const response = await apiClient.get('/health');
    return response.data;
  },
  
  // Authentication
  login: async (credentials: { email: string; password: string }): Promise<any> => {
    const response = await apiClient.post('/auth/login', credentials);
    return response.data;
  },
  
  logout: async (): Promise<void> => {
    await apiClient.post('/auth/logout');
    localStorage.removeItem('auth_token');
    localStorage.removeItem('refresh_token');
  },
  
  // User Management
  getCurrentUser: async (): Promise<any> => {
    const response = await apiClient.get('/users/me');
    return response.data;
  },
  
  updateUser: async (userId: string, data: any): Promise<any> => {
    const response = await apiClient.put(`/users/${userId}`, data);
    return response.data;
  },
  
  // Data Operations
  fetchData: async (endpoint: string, params?: any): Promise<any> => {
    const response = await apiClient.get(endpoint, { params });
    return response.data;
  },
  
  createData: async (endpoint: string, data: any): Promise<any> => {
    const response = await apiClient.post(endpoint, data);
    return response.data;
  },
  
  updateData: async (endpoint: string, id: string, data: any): Promise<any> => {
    const response = await apiClient.put(`${endpoint}/${id}`, data);
    return response.data;
  },
  
  deleteData: async (endpoint: string, id: string): Promise<void> => {
    await apiClient.delete(`${endpoint}/${id}`);
  },
  
  // File Upload
  uploadFile: async (file: File, onProgress?: (progress: number) => void): Promise<any> => {
    const formData = new FormData();
    formData.append('file', file);
    
    const config: AxiosRequestConfig = {
      headers: {
        'Content-Type': 'multipart/form-data',
      },
      onUploadProgress: (progressEvent: any) => {
        const percentCompleted = Math.round((progressEvent.loaded * 100) / progressEvent.total);
        onProgress?.(percentCompleted);
      },
    };
    
    const response = await apiClient.post('/files/upload', formData, config);
    return response.data;
  },
  
  // Analytics
  trackEvent: async (eventName: string, properties?: any): Promise<void> => {
    if (process.env.REACT_APP_ENABLE_ANALYTICS === 'true') {
      await apiClient.post('/analytics/events', {
        event: eventName,
        properties,
        timestamp: new Date().toISOString(),
      });
    }
  },
};

// Utility Functions
function generateRequestId(): string {
  return `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
}

// Custom hook for API calls with React Query
export const useApiQuery = (key: string, fetcher: () => Promise<any>, options?: any) => {
  return {
    queryKey: [key],
    queryFn: fetcher,
    ...options,
  };
};

export default apiClient;
