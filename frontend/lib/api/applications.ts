import { httpClient } from "./client";
import { AppFormResponse, DynamicFormData } from "../types/app-form";

export const applicationApi = {
  async getFormSchema(appName: string): Promise<AppFormResponse> {
    return httpClient.request<AppFormResponse>(`/applications/${appName}`);
  },

  async validateAppConfig(appName: string, currentConfig: DynamicFormData): Promise<AppFormResponse> {
    return httpClient.request<AppFormResponse>(`/applications/${appName}/validate`, {
      method: 'POST',
      body: JSON.stringify({ config: currentConfig }),
    });
  },
};

