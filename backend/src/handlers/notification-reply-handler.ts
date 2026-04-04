import { handleChatRequest } from './text-handler.js';

type ApiEvent = Parameters<typeof handleChatRequest>[0];
type ApiResponse = Awaited<ReturnType<typeof handleChatRequest>>;

export const handleNotificationReplyRequest = async (
  event: ApiEvent,
): Promise<ApiResponse> => {
  return handleChatRequest(event);
};
