const RepositoryId = @import("repository_id.zig").RepositoryId;
const CategoryId = @import("category_id.zig").CategoryId;

data_file_id: u8,
data_file_offset: u64,
repo_id: RepositoryId,
category_id: CategoryId,
chunk_id: u8,
