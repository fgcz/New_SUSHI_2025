import { useQuery } from "@tanstack/react-query";
import { applicationApi } from "@/lib/api";

export function useApplicationFormSchema(appName: string) {
  return useQuery({
    queryKey: ["appForm", appName],
    queryFn: () => applicationApi.getFormSchema(appName),
    staleTime: 60_000,
  });
}