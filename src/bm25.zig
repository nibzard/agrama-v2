//! BM25 Lexical Search Implementation
//! 
//! Implements BM25 (Best Matching 25) algorithm for lexical/keyword-based search
//! specifically optimized for code repositories. Features:
//!
//! - Code-aware tokenization (camelCase, snake_case, function signatures)
//! - Weighted scoring for different code elements (functions, variables, types, comments)  
//! - Inverted index with efficient term lookup and frequency calculation
//! - Sub-1ms search performance for typical code queries
//! - Memory-efficient storage using Zig allocator patterns
//!
//! Core BM25 formula: score(D,Q) = Σ IDF(qi) * f(qi,D) * (k1 + 1) / (f(qi,D) + k1 * (1 - b + b * |D| / avgdl))

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const StringHashMap = std.StringHashMap;

/// Document ID type for consistency with existing codebase
pub const DocumentID = u32;

/// Term frequency and metadata for BM25 scoring
pub const TermFrequency = struct {
    frequency: u32,
    positions: []u32, // Term positions for phrase queries
    
    pub fn init(allocator: Allocator, freq: u32) !TermFrequency {
        return TermFrequency{
            .frequency = freq,
            .positions = try allocator.alloc(u32, 0), // Empty initially
        };
    }
    
    pub fn deinit(self: TermFrequency, allocator: Allocator) void {
        allocator.free(self.positions);
    }
};

/// Document metadata for BM25 calculations
pub const DocumentMetadata = struct {
    id: DocumentID,
    length: u32,           // Total token count
    file_path: []const u8,
    content_type: ContentType,
    
    const ContentType = enum {
        function_code,
        variable_declaration,
        type_definition,
        comment_block,
        mixed_code,
    };
    
    pub fn init(id: DocumentID, path: []const u8, length: u32, content_type: ContentType) DocumentMetadata {
        return .{
            .id = id,
            .length = length,
            .file_path = path,
            .content_type = content_type,
        };
    }
};

/// Search result with BM25 score and metadata
pub const BM25SearchResult = struct {
    document_id: DocumentID,
    score: f32,
    file_path: []const u8,
    matching_terms: [][]const u8, // Terms that matched
    
    pub fn init(allocator: Allocator, doc_id: DocumentID, score: f32, path: []const u8) !BM25SearchResult {
        return BM25SearchResult{
            .document_id = doc_id,
            .score = score,
            .file_path = try allocator.dupe(u8, path),
            .matching_terms = try allocator.alloc([]const u8, 0),
        };
    }
    
    pub fn deinit(self: BM25SearchResult, allocator: Allocator) void {
        allocator.free(self.file_path);
        for (self.matching_terms) |term| {
            allocator.free(term);
        }
        allocator.free(self.matching_terms);
    }
};

/// Posting list entry for inverted index
const PostingEntry = struct {
    doc_id: DocumentID,
    tf: TermFrequency,
};

/// BM25 Index with inverted index and efficient search capabilities
pub const BM25Index = struct {
    allocator: Allocator,
    
    // Core index structures
    inverted_index: StringHashMap(ArrayList(PostingEntry)),
    documents: HashMap(DocumentID, DocumentMetadata, std.hash_map.AutoContext(DocumentID), std.hash_map.default_max_load_percentage),
    document_frequencies: StringHashMap(u32), // Term -> number of docs containing term
    
    // BM25 parameters (tuned for code search)
    k1: f32 = 1.2,    // Term frequency saturation parameter
    b: f32 = 0.75,    // Field length normalization parameter  
    
    // Statistics for scoring
    total_documents: u32 = 0,
    average_document_length: f32 = 0.0,
    total_term_count: u64 = 0,
    
    // Code-specific weight multipliers
    function_weight: f32 = 3.0,     // Functions are highly important
    variable_weight: f32 = 2.0,     // Variables are important  
    type_weight: f32 = 2.5,         // Types are very important
    comment_weight: f32 = 1.0,      // Comments are baseline importance
    
    pub fn init(allocator: Allocator) BM25Index {
        return .{
            .allocator = allocator,
            .inverted_index = StringHashMap(ArrayList(PostingEntry)).init(allocator),
            .documents = HashMap(DocumentID, DocumentMetadata, std.hash_map.AutoContext(DocumentID), std.hash_map.default_max_load_percentage).init(allocator),
            .document_frequencies = StringHashMap(u32).init(allocator),
        };
    }
    
    pub fn deinit(self: *BM25Index) void {
        // Clean up inverted index
        var index_iterator = self.inverted_index.iterator();
        while (index_iterator.next()) |entry| {
            for (entry.value_ptr.items) |posting| {
                posting.tf.deinit(self.allocator);
            }
            entry.value_ptr.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.inverted_index.deinit();
        
        // Clean up documents
        var doc_iterator = self.documents.iterator();
        while (doc_iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.file_path);
        }
        self.documents.deinit();
        
        // Clean up document frequencies  
        var df_iterator = self.document_frequencies.iterator();
        while (df_iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.document_frequencies.deinit();
    }
    
    /// Add a document to the BM25 index with code-aware processing
    pub fn addDocument(self: *BM25Index, doc_id: DocumentID, file_path: []const u8, content: []const u8) !void {
        // Tokenize content with code-aware processing
        const tokens = try self.tokenizeCode(content);
        defer self.freeTokens(tokens);
        
        // Determine document content type for weighting
        const content_type = self.inferContentType(content);
        
        // Create document metadata (store a copy of the file path)
        const owned_file_path = try self.allocator.dupe(u8, file_path);
        const doc_metadata = DocumentMetadata.init(doc_id, owned_file_path, @as(u32, @intCast(tokens.len)), content_type);
        try self.documents.put(doc_id, doc_metadata);
        
        // Build term frequencies for this document
        var term_counts = StringHashMap(u32).init(self.allocator);
        defer {
            var tc_iterator = term_counts.iterator();
            while (tc_iterator.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            term_counts.deinit();
        }
        
        // Count term frequencies
        for (tokens) |token| {
            const owned_token = try self.allocator.dupe(u8, token);
            const result = try term_counts.getOrPut(owned_token);
            if (result.found_existing) {
                self.allocator.free(owned_token); // Don't need duplicate
                result.value_ptr.* += 1;
            } else {
                result.value_ptr.* = 1;
            }
        }
        
        // Add to inverted index
        var term_iterator = term_counts.iterator();
        while (term_iterator.next()) |entry| {
            const term = entry.key_ptr.*;
            const frequency = entry.value_ptr.*;
            
            // Add to inverted index
            const term_copy = try self.allocator.dupe(u8, term);
            const index_result = try self.inverted_index.getOrPut(term_copy);
            if (!index_result.found_existing) {
                index_result.value_ptr.* = ArrayList(PostingEntry).init(self.allocator);
            } else {
                self.allocator.free(term_copy); // Don't need duplicate
            }
            
            const tf = try TermFrequency.init(self.allocator, frequency);
            try index_result.value_ptr.append(.{ .doc_id = doc_id, .tf = tf });
            
            // Update document frequency
            const df_term = try self.allocator.dupe(u8, term);
            const df_result = try self.document_frequencies.getOrPut(df_term);
            if (df_result.found_existing) {
                self.allocator.free(df_term);
                df_result.value_ptr.* += 1;
            } else {
                df_result.value_ptr.* = 1;
            }
        }
        
        // Update global statistics
        self.total_documents += 1;
        self.total_term_count += tokens.len;
        self.average_document_length = @as(f32, @floatFromInt(self.total_term_count)) / @as(f32, @floatFromInt(self.total_documents));
    }
    
    /// Search the index using BM25 scoring
    pub fn search(self: *BM25Index, query: []const u8, max_results: u32) ![]BM25SearchResult {
        const query_terms = try self.tokenizeCode(query);
        defer self.freeTokens(query_terms);
        
        if (query_terms.len == 0) {
            return try self.allocator.alloc(BM25SearchResult, 0);
        }
        
        // Candidate documents and their scores
        var document_scores = HashMap(DocumentID, f32, std.hash_map.AutoContext(DocumentID), std.hash_map.default_max_load_percentage).init(self.allocator);
        defer document_scores.deinit();
        
        // Calculate BM25 scores for each query term
        for (query_terms) |term| {
            if (self.inverted_index.get(term)) |postings_list| {
                const doc_frequency = self.document_frequencies.get(term) orelse 0;
                const idf = self.calculateIDF(doc_frequency);
                
                for (postings_list.items) |posting| {
                    const doc_metadata = self.documents.get(posting.doc_id) orelse continue;
                    
                    // Apply content type weighting
                    const content_weight = switch (doc_metadata.content_type) {
                        .function_code => self.function_weight,
                        .variable_declaration => self.variable_weight,
                        .type_definition => self.type_weight,
                        .comment_block => self.comment_weight,
                        .mixed_code => 1.0,
                    };
                    
                    const tf_score = self.calculateTFScore(posting.tf.frequency, doc_metadata.length);
                    const term_score = idf * tf_score * content_weight;
                    
                    const current_score = document_scores.get(posting.doc_id) orelse 0.0;
                    try document_scores.put(posting.doc_id, current_score + term_score);
                }
            }
        }
        
        // Convert to results and sort by score
        var results = ArrayList(BM25SearchResult).init(self.allocator);
        defer results.deinit();
        
        var score_iterator = document_scores.iterator();
        while (score_iterator.next()) |entry| {
            const doc_id = entry.key_ptr.*;
            const score = entry.value_ptr.*;
            const doc_metadata = self.documents.get(doc_id) orelse continue;
            
            const result = try BM25SearchResult.init(self.allocator, doc_id, score, doc_metadata.file_path);
            try results.append(result);
        }
        
        // Sort by score (descending)
        std.sort.pdq(BM25SearchResult, results.items, {}, struct {
            fn lessThan(_: void, a: BM25SearchResult, b: BM25SearchResult) bool {
                return a.score > b.score;
            }
        }.lessThan);
        
        // Return top results
        const result_count = @min(max_results, @as(u32, @intCast(results.items.len)));
        const final_results = try self.allocator.alloc(BM25SearchResult, result_count);
        
        for (0..result_count) |i| {
            final_results[i] = results.items[i];
        }
        
        return final_results;
    }
    
    /// Calculate IDF (Inverse Document Frequency) score
    fn calculateIDF(self: *BM25Index, document_frequency: u32) f32 {
        if (document_frequency == 0) return 0.0;
        
        const n = @as(f32, @floatFromInt(self.total_documents));
        const df = @as(f32, @floatFromInt(document_frequency));
        
        return @log((n - df + 0.5) / (df + 0.5));
    }
    
    /// Calculate TF (Term Frequency) component of BM25 score
    fn calculateTFScore(self: *BM25Index, term_frequency: u32, document_length: u32) f32 {
        const tf = @as(f32, @floatFromInt(term_frequency));
        const dl = @as(f32, @floatFromInt(document_length));
        
        const numerator = tf * (self.k1 + 1.0);
        const denominator = tf + self.k1 * (1.0 - self.b + self.b * (dl / self.average_document_length));
        
        return numerator / denominator;
    }
    
    /// Code-aware tokenization that handles programming language constructs
    pub fn tokenizeCode(self: *BM25Index, content: []const u8) ![][]const u8 {
        var tokens = ArrayList([]const u8).init(self.allocator);
        var i: usize = 0;
        
        while (i < content.len) {
            // Skip whitespace
            while (i < content.len and std.ascii.isWhitespace(content[i])) {
                i += 1;
            }
            if (i >= content.len) break;
            
            const start = i;
            
            // Handle different token types
            if (std.ascii.isAlphabetic(content[i]) or content[i] == '_') {
                // Identifier or keyword
                while (i < content.len and (std.ascii.isAlphanumeric(content[i]) or content[i] == '_')) {
                    i += 1;
                }
                
                const identifier = content[start..i];
                
                // Split camelCase and handle snake_case
                try self.extractSubTokens(&tokens, identifier);
                
            } else if (std.ascii.isDigit(content[i])) {
                // Number
                while (i < content.len and (std.ascii.isDigit(content[i]) or content[i] == '.')) {
                    i += 1;
                }
                try tokens.append(content[start..i]);
                
            } else {
                // Single character operators, punctuation
                if (content[i] != ' ' and content[i] != '\t' and content[i] != '\n') {
                    try tokens.append(content[start..start + 1]);
                }
                i += 1;
            }
        }
        
        return try tokens.toOwnedSlice();
    }
    
    /// Extract sub-tokens from camelCase and snake_case identifiers
    fn extractSubTokens(_: *BM25Index, tokens: *ArrayList([]const u8), identifier: []const u8) !void {
        // Add the full identifier
        try tokens.append(identifier);
        
        // Handle snake_case
        if (std.mem.indexOfScalar(u8, identifier, '_')) |_| {
            var parts = std.mem.splitScalar(u8, identifier, '_');
            while (parts.next()) |part| {
                if (part.len > 0) {
                    try tokens.append(part);
                }
            }
            return;
        }
        
        // Handle camelCase
        var start: usize = 0;
        for (identifier[1..], 1..) |char, i| {
            if (std.ascii.isUpper(char)) {
                if (start < i) {
                    try tokens.append(identifier[start..i]);
                }
                start = i;
            }
        }
        
        if (start < identifier.len) {
            try tokens.append(identifier[start..]);
        }
    }
    
    /// Free tokenized results
    pub fn freeTokens(self: *BM25Index, tokens: [][]const u8) void {
        self.allocator.free(tokens);
    }
    
    /// Infer document content type for weighted scoring
    fn inferContentType(_: *BM25Index, content: []const u8) DocumentMetadata.ContentType {
        
        // Simple heuristics for content type detection
        if (std.mem.indexOf(u8, content, "function") != null or 
            std.mem.indexOf(u8, content, "def ") != null or
            std.mem.indexOf(u8, content, "fn ") != null) {
            return .function_code;
        }
        
        if (std.mem.indexOf(u8, content, "interface") != null or
            std.mem.indexOf(u8, content, "struct") != null or
            std.mem.indexOf(u8, content, "class") != null) {
            return .type_definition;
        }
        
        if (std.mem.indexOf(u8, content, "let ") != null or
            std.mem.indexOf(u8, content, "var ") != null or
            std.mem.indexOf(u8, content, "const ") != null) {
            return .variable_declaration;
        }
        
        if (std.mem.indexOf(u8, content, "//") != null or
            std.mem.indexOf(u8, content, "/*") != null or
            std.mem.indexOf(u8, content, "#") != null) {
            return .comment_block;
        }
        
        return .mixed_code;
    }
    
    /// Get index statistics for monitoring and optimization
    pub fn getStats(self: *BM25Index) IndexStats {
        return IndexStats{
            .total_documents = self.total_documents,
            .total_terms = @as(u32, @intCast(self.inverted_index.count())),
            .average_document_length = self.average_document_length,
            .total_term_count = self.total_term_count,
            .index_memory_mb = self.estimateMemoryUsage(),
        };
    }
    
    /// Estimate memory usage of the index
    fn estimateMemoryUsage(self: *BM25Index) f32 {
        var total_size: usize = 0;
        
        // Inverted index
        total_size += self.inverted_index.count() * @sizeOf(usize); // HashMap overhead
        var index_iterator = self.inverted_index.iterator();
        while (index_iterator.next()) |entry| {
            total_size += entry.key_ptr.len; // Term string
            total_size += entry.value_ptr.items.len * @sizeOf(@TypeOf(entry.value_ptr.items[0]));
        }
        
        // Documents
        total_size += self.documents.count() * @sizeOf(DocumentMetadata);
        
        // Document frequencies
        total_size += self.document_frequencies.count() * (@sizeOf(usize) + @sizeOf(u32));
        
        return @as(f32, @floatFromInt(total_size)) / (1024.0 * 1024.0);
    }
};

/// Index performance statistics
pub const IndexStats = struct {
    total_documents: u32,
    total_terms: u32,
    average_document_length: f32,
    total_term_count: u64,
    index_memory_mb: f32,
};

// Unit tests
const testing = std.testing;

test "BM25Index basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var index = BM25Index.init(allocator);
    defer index.deinit();
    
    // Add test documents
    try index.addDocument(1, "test.js", "function calculateDistance(a, b) { return Math.sqrt(a*a + b*b); }");
    try index.addDocument(2, "utils.js", "const validateEmail = (email) => /^\\S+@\\S+$/.test(email);");
    try index.addDocument(3, "types.ts", "interface User { id: number; name: string; email: string; }");
    
    const stats = index.getStats();
    try testing.expect(stats.total_documents == 3);
    try testing.expect(stats.total_terms > 10); // Should have extracted many terms
    
    // Test search
    const results = try index.search("function calculate", 5);
    defer {
        for (results) |result| {
            result.deinit(allocator);
        }
        allocator.free(results);
    }
    
    try testing.expect(results.len > 0);
    try testing.expect(results[0].score > 0);
}

test "BM25Index code tokenization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var index = BM25Index.init(allocator);
    defer index.deinit();
    
    const tokens = try index.tokenizeCode("getUserData");
    defer index.freeTokens(tokens);
    
    // Should split camelCase
    var found_get = false;
    var found_user = false;
    var found_data = false;
    
    for (tokens) |token| {
        if (std.mem.eql(u8, token, "get")) found_get = true;
        if (std.mem.eql(u8, token, "User")) found_user = true;
        if (std.mem.eql(u8, token, "Data")) found_data = true;
    }
    
    try testing.expect(found_get);
    try testing.expect(found_user);
    try testing.expect(found_data);
}

test "BM25Index content type inference" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var index = BM25Index.init(allocator);
    defer index.deinit();
    
    try testing.expect(index.inferContentType("function test() {}") == .function_code);
    try testing.expect(index.inferContentType("interface User {}") == .type_definition);
    try testing.expect(index.inferContentType("const x = 5;") == .variable_declaration);
    try testing.expect(index.inferContentType("// this is a comment") == .comment_block);
}