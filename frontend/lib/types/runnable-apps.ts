export interface RunnableApp {
  category: string;
  applications: string[];
}

export type RunnableAppsResponse = RunnableApp[];