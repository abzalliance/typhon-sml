(* HPaxos Message *)

signature HPAXOS_VALUE =
sig
    type t
    val default : t (* default value *)
    val eq : t * t -> bool (* equality *)
end

signature HPAXOS_BALLOT =
sig
    type t
    val zero : t (* the smallest ballot *)
    val eq : t * t -> bool
    val compare : t * t -> order
end

signature HPAXOS_MESSAGE =
sig
    type t

    structure Value : HPAXOS_VALUE
    type value = Value.t

    structure Ballot : HPAXOS_BALLOT
    type ballot = Ballot.t

    structure Learner : LEARNER
    type learner = Learner.t

    structure Acceptor : ACCEPTOR
    type acceptor = Acceptor.t

    val hash : t -> word
    val eq : t * t -> bool

    val is_one_a : t -> bool
    val is_one_b : t -> bool
    val is_two_a : t -> bool

    (* if the message is 2a, return its learner instance; otherwise, return NONE *)
    val learner : t -> learner option

    (* returns message sender *)
    val sender : t -> acceptor

    (* if the message is 1a, return its ballot and value; otherwise, return NONE *)
    val get_bal_val : t -> (ballot * value) option

    (* returns a previous message of the sender *)
    val get_prev : t -> t option

    (* returns a list of direct references *)
    val get_refs : t -> t list
end

functor MessageOrdKey (Msg : HPAXOS_MESSAGE) : ORD_KEY =
struct
    type ord_key = Msg.t
    fun compare (m1, m2) = Word.compare (Msg.hash m1, Msg.hash m2)
end

functor MessageUtil (Msg : HPAXOS_MESSAGE) =
struct
    structure MsgSet : ORD_SET = RedBlackSetFn (MessageOrdKey (Msg))

    (* checks if m2 is in transitive closure of prev for m1 *)
    structure PrevTran :>
              sig
                  val is_prev_reachable : Msg.t * Msg.t -> bool
                  val is_prev_reachable' : (Msg.t -> Msg.Ballot.t) -> Msg.t * Msg.t -> bool
              end =
    struct
    fun is_prev_reachable_aux cont (m1, m2) =
        let fun doit NONE = false
              | doit (SOME m) =
                cont m andalso (Msg.eq (m, m2) orelse doit (Msg.get_prev m))
        in
            doit (SOME m1)
        end

    fun is_prev_reachable (x, y) =
        is_prev_reachable_aux (fn z => true) (x, y)

    fun is_prev_reachable' bal (x, y) =
        let
            val y_bal = bal y
            fun cont z =
                case Msg.Ballot.compare (bal z, y_bal) of
                    LESS => false
                  | _ => true
        in
            is_prev_reachable_aux cont (x, y)
        end
    end (* PrevTran *)

    (* compute transitive references of the message *)
    fun tran pred cont m =
        let
            fun doit accu visited [] = accu
              | doit accu visited (x :: tl) =
                if MsgSet.member (visited, x) then
                    doit accu visited tl
                else
                    let val visited' = MsgSet.add (visited, x) in
                        if cont x then
                            let
                                val accu' = if pred x then x :: accu else accu
                                val queue' = (Msg.get_refs x) @ tl
                            in
                                doit accu' visited' queue'
                            end
                        else
                            doit accu visited' tl
                    end
        in
            doit [] MsgSet.empty [m]
        end
end
