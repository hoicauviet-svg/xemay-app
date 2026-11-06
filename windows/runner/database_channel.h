#ifndef RUNNER_DATABASE_CHANNEL_H_
#define RUNNER_DATABASE_CHANNEL_H_

namespace flutter {
class BinaryMessenger;
}

void RegisterDatabaseChannel(flutter::BinaryMessenger* messenger);
void ResetDatabaseChannel();

#endif  // RUNNER_DATABASE_CHANNEL_H_
