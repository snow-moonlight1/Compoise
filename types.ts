
export enum QuadrantType {
  Do = 1,       // Urgent & Important
  Plan = 2,     // Not Urgent & Important
  Delegate = 3, // Urgent & Not Important
  Eliminate = 4 // Not Urgent & Not Important
}

export interface Board {
  id: string;
  name: string;
  createdAt: number;
}

export interface Task {
  id: string;
  boardId: string; // Added board association
  title: string;
  quadrant: QuadrantType;
  isLongTerm: boolean;
  completed: boolean;
  createdAt: number;
}

export interface AIAnalysisResult {
  title: string;
  quadrant: QuadrantType;
  isLongTerm: boolean;
  reasoning?: string;
}

export enum AIProvider {
  Gemini = 'gemini',
  Custom = 'custom'
}

export type Language = 'en' | 'zh' | 'ja';
export type ThemeMode = 'system' | 'light' | 'dark';
export type ThemeColor = 'blue' | 'purple' | 'green' | 'orange' | 'pink';
export type InputMode = 'single' | 'brainDump';

export interface AppSettings {
  language: Language;
  theme: ThemeMode;
  themeColor: ThemeColor; // Added theme color
  defaultInputMode: InputMode;
}

export interface AIConfig {
  provider: AIProvider;
  customBaseUrl?: string;
  customApiKey?: string;
  customModel?: string;
}

// SVG Icon Props
export interface IconProps {
  className?: string;
  size?: number;
}
