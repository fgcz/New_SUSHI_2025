import { httpClient } from "./client";
import { AppFormResponse } from "../types/app-form";

export const applicationApi = {
  async getFormSchema(appName: string): Promise<AppFormResponse> {
    return httpClient.request<AppFormResponse>(`/api/v1/application_configs/${appName}`, {
      method: 'GET',
    });
  },
};

