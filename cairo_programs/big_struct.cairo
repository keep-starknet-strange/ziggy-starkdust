from starkware.cairo.common.dict import DictAccess

struct VotingState {
    n_yes_votes: felt,
    n_no_votes: felt,
    public_key_tree_start: DictAccess*,
    public_key_tree_end: DictAccess*,
}

struct VoteInfo {
    voter_id: felt,
    pub_key: felt,
    vote: felt,
    r: felt,
    s: felt,
}

struct BatchOutput {
    n_yes_votes: felt,
    n_no_votes: felt,
    public_keys_root_before: felt,
    public_keys_root_after: felt,
}

func main{}() {
    ret;
}
