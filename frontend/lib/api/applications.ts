import { httpClient } from "./client";
import { AppFormResponse, DynamicFormData } from "../types/app-form";

export const applicationApi = {
  async getFormSchema(appName: string): Promise<AppFormResponse> {
    return httpClient.request<AppFormResponse>(`/api/v1/application_configs/${appName}`, {
      method: 'GET',
    });
  },

  // NOTE: the backend has no validate route yet, so this rejects and
  // useApplicationForm swallows the error. Blurring a field simply does not
  // re-derive defaults; legacy has no live validation either.
  async validateAppConfig(appName: string, currentConfig: DynamicFormData): Promise<AppFormResponse> {
    return httpClient.request<AppFormResponse>(`/api/v1/application_configs/${appName}/validate`, {
      method: 'POST',
      body: JSON.stringify({ config: currentConfig }),
    });
  },
};
