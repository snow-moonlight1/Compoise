import React from 'react';
import { AppSettings } from '../types';
import { ToggleSwitch } from './ui/ToggleSwitch';

interface SettingsControlsProps {
  settings: AppSettings;
  setSettings: React.Dispatch<React.SetStateAction<AppSettings>>;
  readOnly?: boolean;
  t: any;
}

export const SettingsControls: React.FC<SettingsControlsProps> = ({ settings, setSettings, readOnly = false, t }) => {
  return (
      <div className="neu-flat rounded-xl p-3 space-y-4">
          {/* Auto Decompose Toggle */}
          <div className="flex items-center justify-between">
              <div>
                  <p className="text-sm font-bold text-slate-700 dark:text-slate-200">{t.autoDecomposeAI}</p>
                  <p className="text-xs text-slate-500">{t.autoDecomposeDesc}</p>
              </div>
              <ToggleSwitch 
                  checked={settings.autoDecomposeAI} 
                  onChange={() => !readOnly && setSettings(s => ({ ...s, autoDecomposeAI: !s.autoDecomposeAI }))}
              />
          </div>

          {/* Suppress Decompose Prompt */}
          <div className="flex items-center justify-between">
              <div>
                  <p className="text-sm font-bold text-slate-700 dark:text-slate-200">{t.suppressLongTermPrompt}</p>
              </div>
              <ToggleSwitch 
                  checked={settings.suppressLongTermPrompt} 
                  onChange={() => !readOnly && setSettings(s => ({ ...s, suppressLongTermPrompt: !s.suppressLongTermPrompt }))}
              />
          </div>

          <div className="h-px bg-slate-200 dark:bg-slate-700"></div>

          {/* Auto Group Toggle */}
          <div className="flex items-center justify-between">
              <div>
                  <p className="text-sm font-bold text-slate-700 dark:text-slate-200">{t.autoGroupAI}</p>
                  <p className="text-xs text-slate-500">{t.autoGroupDesc}</p>
              </div>
              <ToggleSwitch 
                  checked={settings.autoGroupAI} 
                  onChange={() => !readOnly && setSettings(s => ({ ...s, autoGroupAI: !s.autoGroupAI }))}
              />
          </div>

          {/* Suppress Group Prompt */}
          <div className="flex items-center justify-between">
              <div>
                  <p className="text-sm font-bold text-slate-700 dark:text-slate-200">{t.suppressGroupPrompt}</p>
              </div>
              <ToggleSwitch 
                  checked={settings.suppressGroupPrompt} 
                  onChange={() => !readOnly && setSettings(s => ({ ...s, suppressGroupPrompt: !s.suppressGroupPrompt }))}
              />
          </div>
          
          <div className="h-px bg-slate-200 dark:bg-slate-700"></div>

           {/* Urgency Threshold */}
          <div>
             <div className="flex justify-between mb-1">
               <p className="text-sm font-bold text-slate-700 dark:text-slate-200">{t.urgencyThreshold}</p>
               <span className="text-xs font-bold text-primary bg-primary/10 px-2 rounded">{settings.urgencyThresholdDays} {t.daysLeft.split(' ')[0]}</span>
             </div>
             <input 
               type="range" 
               min="1" max="14" 
               value={settings.urgencyThresholdDays} 
               onChange={(e) => !readOnly && setSettings(s => ({ ...s, urgencyThresholdDays: parseInt(e.target.value) }))}
               className="w-full accent-primary h-1 bg-slate-300 rounded-lg appearance-none cursor-pointer"
               disabled={readOnly}
             />
          </div>
      </div>
  );
};