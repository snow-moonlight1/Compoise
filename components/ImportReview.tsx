

import React from 'react';
import { AppSettings, ExportData } from '../types';
import { Checkbox } from './ui/Checkbox';

interface ImportReviewProps {
  settings: AppSettings;
  pendingImport: ExportData | null;
  importSelection: Set<string>;
  setImportSelection: (selection: Set<string>) => void;
  t: any;
}

export const ImportReview: React.FC<ImportReviewProps> = ({ settings, pendingImport, importSelection, setImportSelection, t }) => {
    const boolText = (val: boolean) => val ? 'ON' : 'OFF';
      
    // Automation Group Logic
    const automationKeys = ['autoDecomposeAI', 'suppressLongTermPrompt', 'autoGroupAI', 'suppressGroupPrompt', 'urgencyThresholdDays', 'autoCompleteParent'];
    const isAllAutoSelected = automationKeys.every(k => importSelection.has(k));
    
    const toggleAutomationGroup = () => {
        const newSet = new Set(importSelection);
        if (isAllAutoSelected) {
            automationKeys.forEach(k => newSet.delete(k));
        } else {
            automationKeys.forEach(k => newSet.add(k));
        }
        setImportSelection(newSet);
    };

    const renderImportRow = (key: string, label: string, value: React.ReactNode) => {
        const toggle = () => {
            const newSet = new Set(importSelection);
            if (newSet.has(key)) newSet.delete(key);
            else newSet.add(key);
            setImportSelection(newSet);
        };

        return (
          <div 
              onClick={toggle}
              className={`flex items-center gap-3 p-2 rounded-lg cursor-pointer transition-colors ${importSelection.has(key) ? 'bg-primary/5' : 'hover:bg-slate-100 dark:hover:bg-slate-800'}`}
          >
              <Checkbox checked={importSelection.has(key)} onChange={toggle} />
              <div className="flex-1 flex justify-between text-sm">
                  <span className="text-slate-500">{label}:</span>
                  <span className={`font-bold ${importSelection.has(key) ? 'text-slate-700 dark:text-slate-200' : 'text-slate-400 decoration-slate-400 line-through'}`}>
                      {value}
                  </span>
              </div>
          </div>
        );
    };

    return (
        <div className="neu-flat rounded-xl p-3 space-y-1">
             {renderImportRow('language', t.language, <span className="uppercase">{settings.language}</span>)}
             {renderImportRow('theme', t.theme, <span className="capitalize">{settings.theme}</span>)}
             {renderImportRow('themeColor', t.themeColor, (
                 <div className="flex items-center gap-2">
                     <span className="capitalize">{settings.themeColor}</span>
                     <div className="w-3 h-3 rounded-full" style={{ 
                         backgroundColor: settings.themeColor === 'blue' ? '#3b82f6' : 
                                         settings.themeColor === 'purple' ? '#8b5cf6' : 
                                         settings.themeColor === 'green' ? '#10b981' : 
                                         settings.themeColor === 'orange' ? '#f97316' : '#ec4899' 
                     }}></div>
                 </div>
             ))}
             {renderImportRow('inputMode', t.defaultMode, settings.defaultInputMode === 'single' ? t.modeManual : t.modeAI)}
             
             {pendingImport?.aiConfig && (
                 renderImportRow('aiProvider', t.provider, <span className="capitalize">{pendingImport.aiConfig.provider}</span>)
             )}

             {/* Granular Automation Settings Group */}
             <div className="pt-2">
                 <div 
                    onClick={toggleAutomationGroup}
                    className={`flex items-center gap-3 p-2 rounded-lg cursor-pointer transition-colors ${isAllAutoSelected ? 'bg-primary/10' : 'hover:bg-slate-100 dark:hover:bg-slate-800'}`}
                 >
                      <Checkbox checked={isAllAutoSelected} onChange={toggleAutomationGroup} />
                      <span className="text-sm font-bold text-slate-700 dark:text-slate-200 uppercase tracking-wider">{t.grouping}</span>
                 </div>
                 
                 <div className="pl-6 space-y-1 mt-1 border-l-2 border-slate-200 dark:border-slate-700 ml-3">
                      {renderImportRow('autoDecomposeAI', t.autoDecomposeAI, boolText(settings.autoDecomposeAI))}
                      {renderImportRow('suppressLongTermPrompt', t.suppressLongTermPrompt, boolText(settings.suppressLongTermPrompt))}
                      {renderImportRow('autoGroupAI', t.autoGroupAI, boolText(settings.autoGroupAI))}
                      {renderImportRow('suppressGroupPrompt', t.suppressGroupPrompt, boolText(settings.suppressGroupPrompt))}
                      {renderImportRow('autoCompleteParent', t.autoCompleteParent, boolText(settings.autoCompleteParent))}
                      {renderImportRow('urgencyThresholdDays', t.urgencyThreshold, `${settings.urgencyThresholdDays} d`)}
                 </div>
             </div>

        </div>
    );
};