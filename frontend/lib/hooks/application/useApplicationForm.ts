import { useState, useEffect } from 'react';
import { applicationApi } from '@/lib/api';
import { DynamicFormData, ParamGroup } from '@/lib/types';
import { initializeFormDataFromGroups, flattenParamGroups } from '@/lib/utils/form-renderer';

interface UseApplicationFormParams {
  appName: string;
  datasetId: number;
  datasetName: string | undefined;
  paramGroups: ParamGroup[] | undefined;
  resubmitParams: Record<string, any> | undefined;
  isResubmit: boolean;
}

interface NextDatasetData {
  datasetName: string;
  datasetComment: string;
}

const STORAGE_KEY = 'sushi_job_submission_data';

interface StoredJobData {
  datasetId: number;
  appName: string;
  nextDataset: { name: string; comment?: string };
  parameters: Record<string, any>;
}

function getStoredJobData(appName: string, datasetId: number): StoredJobData | null {
  try {
    const stored = sessionStorage.getItem(STORAGE_KEY);
    if (!stored) return null;

    const data = JSON.parse(stored) as StoredJobData;
    // Only use stored data if it matches the current app and dataset
    if (data.appName === appName && data.datasetId === datasetId) {
      return data;
    }
    return null;
  } catch {
    return null;
  }
}

export function useApplicationForm({
  appName,
  datasetId,
  datasetName,
  paramGroups,
  resubmitParams,
  isResubmit,
}: UseApplicationFormParams) {
  // ============================================
  // STATE
  // ============================================
  const [nextDatasetData, setNextDatasetData] = useState<NextDatasetData>({
    datasetName: 'Loading...',
    datasetComment: '',
  });
  const [formValues, setFormValues] = useState<DynamicFormData>({});
  const [groupConfig, setGroupConfig] = useState<ParamGroup[]>([]);

  // ============================================
  // EFFECTS
  // ============================================

  // Update output dataset name when input dataset loads
  useEffect(() => {
    if (datasetName) {
      // Check for stored data first (from Review -> Back navigation)
      const storedData = getStoredJobData(appName, datasetId);
      if (storedData?.nextDataset) {
        setNextDatasetData({
          datasetName: storedData.nextDataset.name,
          datasetComment: storedData.nextDataset.comment || '',
        });
      } else {
        const baseName = `${appName}_${datasetName}_${new Date().toISOString().slice(0, 10)}`;
        setNextDatasetData((prev) => ({
          ...prev,
          datasetName: baseName,
        }));
      }
    }
  }, [datasetName, appName, datasetId]);

  // Initialize form when schema loads (with optional resubmit or stored data prepopulation)
  useEffect(() => {
    if (paramGroups && paramGroups.length > 0) {
      const initialData = initializeFormDataFromGroups(paramGroups);

      // Check for stored data first (from Review -> Back navigation)
      const storedData = getStoredJobData(appName, datasetId);
      if (storedData?.parameters) {
        Object.keys(storedData.parameters).forEach((key) => {
          if (key in initialData) {
            initialData[key] = storedData.parameters[key];
          }
        });
      }
      // If resubmit, merge the previous job's parameters (takes precedence)
      else if (isResubmit && resubmitParams) {
        Object.keys(resubmitParams).forEach((key) => {
          if (key in initialData) {
            initialData[key] = resubmitParams[key];
          }
        });
      }

      setFormValues(initialData);
      setGroupConfig(paramGroups);
    }
  }, [paramGroups, isResubmit, resubmitParams, appName, datasetId]);

  // ============================================
  // HANDLERS
  // ============================================

  const handleInputChange = (
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>
  ) => {
    const { name, value } = e.target;
    setNextDatasetData((prev) => ({
      ...prev,
      [name]: value,
    }));
  };

  const handleFieldChange = (fieldName: string, value: any) => {
    setFormValues((prev) => ({
      ...prev,
      [fieldName]: value,
    }));
  };

  const handleFieldBlur = async (fieldName: string) => {
    // TODO: Re-enable dynamic form updates once we implement proper "touched" field tracking
    // Currently disabled because it overwrites all user input with defaults on every blur
    //
    // try {
    //   const validationResponse = await applicationApi.validateAppConfig(appName, formValues);
    //
    //   if (validationResponse.application?.param_groups) {
    //     setGroupConfig(validationResponse.application.param_groups);
    //
    //     // Update form values with new defaults from validation
    //     const newValues = { ...formValues };
    //     const allFields = flattenParamGroups(validationResponse.application.param_groups);
    //     allFields.forEach((field) => {
    //       if (field.default_value !== undefined) {
    //         newValues[field.name] = field.default_value;
    //       }
    //     });
    //     setFormValues(newValues);
    //   }
    // } catch (error) {
    //   console.error('Validation error:', error);
    // }
  };

  const handleKeyDown = (e: React.KeyboardEvent, fieldName: string) => {
    if (e.key === 'Enter') {
      e.preventDefault();

      const allFields = flattenParamGroups(groupConfig);
      const currentIndex = allFields.findIndex((f) => f.name === fieldName);
      if (currentIndex === -1) return;

      // Find next focusable field (skip sections and disabled fields)
      for (let i = currentIndex + 1; i < allFields.length; i++) {
        const nextField = allFields[i];
        if (nextField.type !== 'section' && !nextField.disabled) {
          const nextElement = document.getElementById(nextField.name);
          if (nextElement) {
            nextElement.focus();
          }
          break;
        }
      }
    }
  };

  // ============================================
  // RETURN
  // ============================================
  return {
    // State
    nextDatasetData,
    formValues,
    paramGroups: groupConfig,

    // Handlers
    handleInputChange,
    handleFieldChange,
    handleFieldBlur,
    handleKeyDown,
  };
}
